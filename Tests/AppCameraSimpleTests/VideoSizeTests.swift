import XCTest
@testable import AppCameraSimpleCore

final class VideoSizeTests: XCTestCase {
    private let builtIn = CameraFormat(width: 1920, height: 1080, fps: 30)

    private func dims(_ size: VideoSize, _ camera: CameraFormat) -> [Int] {
        let d = size.dimensions(for: camera)
        return [d.width, d.height]
    }

    func testBuiltInCameraOffersEverythingBelowIt() {
        XCTAssertEqual(VideoSize.available(for: builtIn), [.original, .p720, .p540, .p480, .p360, .p240, .p144])
    }

    func testBiggerCameraAlsoOffers1080p() {
        let uhd = CameraFormat(width: 3840, height: 2160, fps: 30)
        XCTAssertEqual(VideoSize.available(for: uhd).prefix(2), [.original, .p1080])
    }

    func testSmallCameraOffersOnlySmaller() {
        let vga = CameraFormat(width: 640, height: 480, fps: 30)
        XCTAssertEqual(VideoSize.available(for: vga), [.original, .p360, .p240, .p144])
    }

    func testSixteenByNineMatchesYouTube() {
        XCTAssertEqual(dims(.original, builtIn), [1920, 1080])
        XCTAssertEqual(dims(.p720, builtIn), [1280, 720])
        XCTAssertEqual(dims(.p540, builtIn), [960, 540])
        XCTAssertEqual(dims(.p480, builtIn), [854, 480])
        XCTAssertEqual(dims(.p360, builtIn), [640, 360])
        XCTAssertEqual(dims(.p240, builtIn), [426, 240])
        XCTAssertEqual(dims(.p144, builtIn), [256, 144])
    }

    func testOtherProportionsGoByShortSide() {
        XCTAssertEqual(dims(.p720, CameraFormat(width: 1760, height: 1328, fps: 30)), [954, 720])
        XCTAssertEqual(dims(.p720, CameraFormat(width: 1080, height: 1920, fps: 30)), [720, 1280])
    }

    func testNeverUpscales() {
        XCTAssertEqual(dims(.p1080, CameraFormat(width: 1280, height: 720, fps: 30)), [1280, 720])
    }

    func testSidesAreEven() {
        for camera in [builtIn, CameraFormat(width: 1760, height: 1328, fps: 30), CameraFormat(width: 1552, height: 1552, fps: 30)] {
            for size in VideoSize.allCases {
                let d = size.dimensions(for: camera)
                XCTAssertEqual(d.width % 2, 0, "\(size) \(camera)")
                XCTAssertEqual(d.height % 2, 0, "\(size) \(camera)")
            }
        }
    }

    func testOriginalBitRateIsTheEncodersOwn() {
        XCTAssertEqual(Double(VideoSize.original.bitRate(for: builtIn)), 14_000_000, accuracy: 500_000)
    }

    func testBitRateFollowsPixelsAndFrameRate() {
        XCTAssertEqual(VideoSize.p540.bitRate(for: builtIn) * 4, VideoSize.original.bitRate(for: builtIn), accuracy: 4)
        let fifteen = CameraFormat(width: 1920, height: 1080, fps: 15)
        XCTAssertEqual(VideoSize.original.bitRate(for: fifteen) * 2, VideoSize.original.bitRate(for: builtIn), accuracy: 2)
    }

    func testBytesPerSecondAddsAudio() {
        let video = VideoSize.p720.bytesPerSecond(for: builtIn, withAudio: false)
        let both = VideoSize.p720.bytesPerSecond(for: builtIn, withAudio: true)
        XCTAssertEqual(both - video, VideoSize.audioBitRate / 8, accuracy: 1)
        XCTAssertEqual(Double(VideoSize.original.bytesPerSecond(for: builtIn, withAudio: true)), 1_800_000, accuracy: 50_000)
    }

    func testNamesRoundTrip() {
        for size in VideoSize.allCases {
            XCTAssertEqual(VideoSize.named(size.displayName), size)
        }
        XCTAssertEqual(VideoSize.p480.displayName, "480p")
        XCTAssertEqual(VideoSize.original.displayName, "Original")
    }

    func testSettingDefaultsToOriginal() {
        XCTAssertEqual(Settings.videoSize.stored(in: makeDefaults()), .original)
        let d = makeDefaults()
        d.set("8k", forKey: Settings.videoSize.storageKey)
        XCTAssertEqual(Settings.videoSize.stored(in: d), .original)
        Settings.videoSize.store(.p480, in: d)
        XCTAssertEqual(Settings.videoSize.stored(in: d), .p480)
    }
}
