import Foundation

/// What the camera delivers: its active format and top frame rate.
public struct CameraFormat: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let fps: Double

    public init(width: Int, height: Int, fps: Double) {
        self.width = width
        self.height = height
        self.fps = fps
    }
}

/// Recorded frame size, named like YouTube's by the short side. Downscaling
/// only, done by the writer, so the preview and photos are untouched.
public enum VideoSize: String, CaseIterable, SettingValue {
    case original
    case p1080, p720, p540, p480, p360, p240, p144

    /// The short side, or nil for whatever the camera gives.
    public var lines: Int? {
        switch self {
        case .original: return nil
        case .p1080: return 1080
        case .p720: return 720
        case .p540: return 540
        case .p480: return 480
        case .p360: return 360
        case .p240: return 240
        case .p144: return 144
        }
    }

    public var displayName: String { lines.map { "\($0)p" } ?? "Original" }

    public static func named(_ displayName: String?) -> VideoSize? {
        allCases.first { $0.displayName == displayName }
    }

    /// Original, then every size smaller than it — never one that would upscale.
    public static func available(for camera: CameraFormat) -> [VideoSize] {
        let short = min(camera.width, camera.height)
        return allCases.filter { size in size.lines.map { $0 < short } ?? true }
    }

    /// Keeps the camera's proportions; both sides even, which H.264 needs. A
    /// size the camera cannot fill falls back to the camera's own.
    public func dimensions(for camera: CameraFormat) -> (width: Int, height: Int) {
        let short = min(camera.width, camera.height)
        guard let lines, lines < short else { return (camera.width, camera.height) }
        let scale = Double(lines) / Double(short)
        func even(_ side: Int) -> Int { max(2, Int((Double(side) * scale / 2).rounded()) * 2) }
        return (even(camera.width), even(camera.height))
    }

    /// Bits per pixel per frame. At 1080p30 this is about 14 Mbit/s, what the
    /// H.264 encoder picks on its own, so Original loses nothing to it — while
    /// a fixed rate makes the size estimate close to exact.
    static let bitsPerPixel = 0.23

    /// AAC as the capture session delivers it, measured on a real recording.
    public static let audioBitRate = 57_000

    public func bitRate(for camera: CameraFormat) -> Int {
        let size = dimensions(for: camera)
        return Int(Double(size.width * size.height) * camera.fps * Self.bitsPerPixel)
    }

    public func bytesPerSecond(for camera: CameraFormat, withAudio: Bool) -> Int {
        (bitRate(for: camera) + (withAudio ? Self.audioBitRate : 0)) / 8
    }
}
