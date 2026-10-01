import XCTest
import CoreGraphics
import ImageIO
@testable import AppCameraSimpleCore

/// Runs the real conversion on pictures drawn here, so no camera is involved.
final class PhotoExportTests: XCTestCase {
    /// A smooth gradient with a little per-pixel noise — detailed enough that
    /// JPEG quality visibly changes the file size.
    private func picture(width: Int = 320, height: Int = 180) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let buffer = context.data!.assumingMemoryBound(to: UInt8.self)
        var seed: UInt32 = 1
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = UInt8(seed >> 28)
                let i = (y * width + x) * 4
                buffer[i] = UInt8(x * 255 / width) &+ noise
                buffer[i + 1] = UInt8(y * 255 / height) &+ noise
                buffer[i + 2] = 128 &+ noise
                buffer[i + 3] = 255
            }
        }
        return context.makeImage()!
    }

    private func decode(_ data: Data) -> (image: CGImage, type: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (image, type as String)
    }

    private func export(_ format: PhotoFormat, scale: Double = 1, quality: Double = 0.85) -> Data {
        PhotoExport.convert(picture(), options: PhotoOptions(format: format, scale: scale, quality: quality))!
    }

    func testWritesTheChosenFormat() {
        XCTAssertEqual(decode(export(.jpeg))?.type, "public.jpeg")
        XCTAssertEqual(decode(export(.png))?.type, "public.png")
    }

    func testFullScaleKeepsOriginalSize() {
        let image = decode(export(.jpeg))!.image
        XCTAssertEqual([image.width, image.height], [320, 180])
    }

    func testScaleShrinksProportionally() {
        let half = decode(export(.png, scale: 0.5))!.image
        XCTAssertEqual([half.width, half.height], [160, 90])
        let third = decode(export(.jpeg, scale: 1.0 / 3))!.image
        XCTAssertEqual([third.width, third.height], [107, 60])
    }

    func testLowerJPEGQualityMakesSmallerFile() {
        XCTAssertLessThan(export(.jpeg, quality: 0.3).count, export(.jpeg, quality: 0.9).count)
    }

    func testPNGIgnoresQuality() {
        XCTAssertEqual(export(.png, quality: 0.1), export(.png, quality: 1))
    }

    func testPNGIsPixelExact() {
        let original = picture()
        let decoded = decode(export(.png))!.image
        XCTAssertEqual(pixels(of: decoded), pixels(of: original))
    }

    /// RGB bytes only, in a known layout, whatever the decoder produced.
    private func pixels(of image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes.enumerated().filter { $0.offset % 4 != 3 }.map(\.element)
    }
}

final class PhotoScaleTests: XCTestCase {
    func testSnapsToNearbyFraction() {
        XCTAssertEqual(PhotoScale.snapped(0.52), 0.5)
        XCTAssertEqual(PhotoScale.snapped(0.34), 1.0 / 3)
        XCTAssertEqual(PhotoScale.snapped(0.98), 1)
    }

    func testLeavesValuesBetweenFractionsAlone() {
        XCTAssertEqual(PhotoScale.snapped(0.58), 0.58)
    }

    func testClampsToRange() {
        XCTAssertEqual(PhotoScale.snapped(5), 1)
        XCTAssertEqual(PhotoScale.snapped(0), 0.1)
        XCTAssertEqual(PhotoOptions(format: .jpeg, scale: 0, quality: 2).scale, 0.1)
        XCTAssertEqual(PhotoOptions(format: .jpeg, scale: 0, quality: 2).quality, 1)
    }

    func testSizeRoundsAndNeverVanishes() {
        XCTAssertTrue(PhotoScale.size(width: 1920, height: 1080, scale: 0.5) == (960, 540))
        XCTAssertTrue(PhotoScale.size(width: 1920, height: 1080, scale: 2.0 / 3) == (1280, 720))
        XCTAssertTrue(PhotoScale.size(width: 3, height: 3, scale: 0.1) == (1, 1))
    }
}

final class PhotoEstimateTests: XCTestCase {
    private func estimate(_ format: PhotoFormat, scale: Double = 1, quality: Double = 0.85) -> Int {
        PhotoExport.estimatedBytes(width: 1920, height: 1080,
                                   options: PhotoOptions(format: format, scale: scale, quality: quality))
    }

    /// The numbers measured on the real camera, give or take.
    func testMatchesMeasuredSizes() {
        XCTAssertEqual(Double(estimate(.jpeg)), 316_000, accuracy: 10_000)
        XCTAssertEqual(Double(estimate(.png)), 1_660_000, accuracy: 30_000)
    }

    func testGrowsWithQualityAndScale() {
        XCTAssertLessThan(estimate(.jpeg, quality: 0.3), estimate(.jpeg, quality: 0.7))
        XCTAssertLessThan(estimate(.jpeg, quality: 0.7), estimate(.jpeg, quality: 1))
        XCTAssertLessThan(estimate(.jpeg, scale: 0.5), estimate(.jpeg))
        XCTAssertLessThan(estimate(.jpeg), estimate(.png))
    }

    func testInterpolatesBetweenMeasuredPoints() {
        XCTAssertEqual(PhotoExport.jpegBitsPerPixel(0.6), (0.63 + 0.94) / 2, accuracy: 1e-9)
        XCTAssertEqual(PhotoExport.jpegBitsPerPixel(1), 3.5)
        XCTAssertEqual(PhotoExport.jpegBitsPerPixel(-1), 0.25)
    }
}

final class PhotoSettingsTests: XCTestCase {
    func testDefaults() {
        let options = PhotoOptions.stored(in: makeDefaults())
        XCTAssertEqual(options, PhotoOptions(format: .png, scale: 1, quality: 0.85))
    }

    func testStoredValuesRead() {
        let d = makeDefaults()
        Settings.photoFormat.store(.png, in: d)
        Settings.photoScale.store(0.5, in: d)
        Settings.photoQuality.store(0.4, in: d)
        XCTAssertEqual(PhotoOptions.stored(in: d), PhotoOptions(format: .png, scale: 0.5, quality: 0.4))
    }

    func testGarbageReadsDefault() {
        let d = makeDefaults()
        d.set("webp", forKey: Settings.photoFormat.storageKey)
        d.set("big", forKey: Settings.photoScale.storageKey)
        XCTAssertEqual(PhotoOptions.stored(in: d), PhotoOptions(format: .png, scale: 1, quality: 0.85))
    }

    func testFormatNames() {
        XCTAssertEqual(PhotoFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(PhotoFormat.png.fileExtension, "png")
        XCTAssertEqual(PhotoFormat.named("JPEG"), .jpeg)
        XCTAssertFalse(PhotoFormat.png.hasQuality)
    }
}
