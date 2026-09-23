import Foundation

/// Output container for recorded video. Persisted in `UserDefaults` under
/// `storageKey` as the raw string (`"mov"` / `"mp4"`). Anything missing or
/// unrecognized reads back as `.mp4`, so files are cross-platform by default.
///
/// The `AVFileType` mapping lives in the exe target's `Recorder`, keeping this
/// type free of AVFoundation so it stays unit-testable.
///
/// Before adding a container here: the mirror has to live in the pixels, never
/// in the video track's display matrix. Recording once went through
/// `AVCaptureMovieFileOutput`, which writes a mirrored connection as the display
/// matrix `[-1 0; 0 1]`. AVFoundation reads that back as the reflection it is,
/// but ffmpeg's `av_display_rotation_get` cannot express a reflection and
/// reduces it to `rotation=-180`, so VLC and anything else built on ffmpeg
/// rotated the clip instead of mirroring it and played it upside down — in
/// `.mov` exactly as much as in `.mp4`, since the matrix is written before the
/// container is even chosen. `Recorder` now mirrors the pixel buffers as they
/// are captured and writes them with `AVAssetWriter`, so files carry no
/// orientation metadata and a new container inherits none of this.
public enum MovieFormat: String, CaseIterable, Sendable {
    case mov
    case mp4

    public static let storageKey = "MovieFormat"
    public static let fallback: MovieFormat = .mp4

    /// File extension for the container, e.g. `mp4`.
    public var fileExtension: String { rawValue }

    /// Human-readable name for menus and pop-ups, e.g. `MP4`.
    public var displayName: String { rawValue.uppercased() }

    /// The stored choice, or `.mp4` when nothing valid is stored.
    public static func stored(in defaults: UserDefaults = .standard) -> MovieFormat {
        defaults.string(forKey: storageKey).flatMap(MovieFormat.init(rawValue:)) ?? fallback
    }

    /// The format matching a `displayName`, or `nil` for anything unrecognized.
    public static func named(_ displayName: String?) -> MovieFormat? {
        displayName.flatMap { MovieFormat(rawValue: $0.lowercased()) }
    }

    /// Persists this choice so the next `stored(in:)` reads it back.
    public func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: MovieFormat.storageKey)
    }
}
