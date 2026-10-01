import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// File format for saved photos. WebP is left out on purpose: ImageIO reads it
/// but cannot write it, and a third-party encoder is not worth the dependency.
public enum PhotoFormat: String, CaseIterable, SettingValue {
    case jpeg
    case png

    public var fileExtension: String { self == .jpeg ? "jpg" : "png" }

    public var displayName: String { rawValue.uppercased() }

    /// PNG is lossless, so there is nothing for a quality setting to trade.
    public var hasQuality: Bool { self == .jpeg }

    var type: UTType { self == .jpeg ? .jpeg : .png }

    public static func named(_ displayName: String?) -> PhotoFormat? {
        displayName.flatMap { PhotoFormat(rawValue: $0.lowercased()) }
    }
}

/// How a captured photo is turned into a file. Everything here is plain
/// ImageIO/CoreGraphics, so it runs — and is tested — without the app or a camera.
public struct PhotoOptions: Sendable, Equatable {
    public var format: PhotoFormat
    /// Fraction of the original width and height, in `PhotoScale.range`.
    public var scale: Double
    /// JPEG quality, 0...1. Ignored for PNG.
    public var quality: Double

    public init(format: PhotoFormat, scale: Double, quality: Double) {
        self.format = format
        self.scale = min(max(scale, PhotoScale.range.lowerBound), PhotoScale.range.upperBound)
        self.quality = min(max(quality, 0), 1)
    }

    public static func stored(in defaults: UserDefaults = .standard) -> PhotoOptions {
        PhotoOptions(format: Settings.photoFormat.stored(in: defaults),
                     scale: Settings.photoScale.stored(in: defaults),
                     quality: Settings.photoQuality.stored(in: defaults))
    }
}

/// Proportional downscaling only — this is a camera, not an editor.
public enum PhotoScale {
    public static let range = 0.1...1.0

    /// The slider snaps to these when released close to one.
    public static let fractions: [Double] = [1, 3.0 / 4, 2.0 / 3, 1.0 / 2, 1.0 / 3, 1.0 / 4, 1.0 / 5, 1.0 / 10]

    static let snapDistance = 0.03

    public static func snapped(_ value: Double) -> Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let nearest = fractions.min { abs($0 - clamped) < abs($1 - clamped) }!
        return abs(nearest - clamped) <= snapDistance ? nearest : clamped
    }

    /// Never rounds a side down to nothing.
    public static func size(width: Int, height: Int, scale: Double) -> (width: Int, height: Int) {
        (max(1, Int((Double(width) * scale).rounded())),
         max(1, Int((Double(height) * scale).rounded())))
    }
}

public enum PhotoExport {
    /// Encodes `image` as a file. No metadata is carried over: the camera's own
    /// JPEG holds nothing worth keeping (no date, no device), only its size.
    public static func convert(_ image: CGImage, options: PhotoOptions) -> Data? {
        guard let pixels = scaled(image, by: options.scale) else { return nil }
        var properties: [String: Any] = [:]
        if options.format.hasQuality {
            properties[kCGImageDestinationLossyCompressionQuality as String] = options.quality
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, options.format.type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, pixels, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// A rough file size for the settings window, from bits per pixel measured
    /// on the built-in 1080p camera (one indoor scene). Real sizes depend on
    /// what is in the frame, hence it is only ever shown as an estimate.
    public static func estimatedBytes(width: Int, height: Int, options: PhotoOptions) -> Int {
        let size = PhotoScale.size(width: width, height: height, scale: options.scale)
        let full = options.format.hasQuality ? jpegBitsPerPixel(options.quality) : 6.4
        // A smaller picture packs the same detail into fewer pixels, so each
        // costs more — measured at about 1/sqrt(scale).
        let bits = Double(size.width * size.height) * full / options.scale.squareRoot()
        return Int(bits / 8)
    }

    /// Measured JPEG bits per pixel at full size, interpolated between points.
    private static let jpegCurve: [(quality: Double, bits: Double)] = [
        (0, 0.25), (0.1, 0.27), (0.3, 0.35), (0.5, 0.63), (0.7, 0.94),
        (0.85, 1.22), (0.95, 1.29), (1, 3.5),
    ]

    static func jpegBitsPerPixel(_ quality: Double) -> Double {
        let q = min(max(quality, 0), 1)
        guard let upper = jpegCurve.firstIndex(where: { $0.quality >= q }), upper > 0 else { return jpegCurve[0].bits }
        let (a, b) = (jpegCurve[upper - 1], jpegCurve[upper])
        return a.bits + (b.bits - a.bits) * (q - a.quality) / (b.quality - a.quality)
    }

    private static func scaled(_ image: CGImage, by scale: Double) -> CGImage? {
        guard scale < 1 else { return image }
        let size = PhotoScale.size(width: image.width, height: image.height, scale: scale)
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: size.width, height: size.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }
}
