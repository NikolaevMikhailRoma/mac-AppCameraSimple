import Foundation

/// Output container for recorded video. Persisted in `UserDefaults` under
/// `storageKey` as the raw string (`"mov"` / `"mp4"`). Anything missing or
/// unrecognized reads back as `.mp4`, so files are cross-platform by default.
///
/// The `AVFileType` mapping lives in the exe target's `Recorder`, keeping this
/// type free of AVFoundation so it stays unit-testable.
public enum MovieFormat: String, CaseIterable, Sendable {
    case mov
    case mp4

    public static let storageKey = "MovieFormat"
    public static let fallback: MovieFormat = .mp4

    /// File extension for the container, e.g. `mp4`.
    public var fileExtension: String { rawValue }

    /// The stored choice, or `.mp4` when nothing valid is stored.
    public static func stored(in defaults: UserDefaults = .standard) -> MovieFormat {
        defaults.string(forKey: storageKey).flatMap(MovieFormat.init(rawValue:)) ?? fallback
    }
}
