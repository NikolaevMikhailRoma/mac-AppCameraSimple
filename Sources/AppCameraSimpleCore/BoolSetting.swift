import Foundation

/// A single on/off preference persisted in `UserDefaults` under `storageKey`.
///
/// `UserDefaults.bool(forKey:)` cannot express "never set" — it reports `false`
/// for a missing key — so the value is read through `object(forKey:)` and falls
/// back to `defaultValue` until the user flips it.
///
/// Like `MovieFormat`, this stays free of AppKit and AVFoundation so it remains
/// unit-testable.
public struct BoolSetting: Sendable {
    public let storageKey: String
    public let defaultValue: Bool

    public init(storageKey: String, defaultValue: Bool) {
        self.storageKey = storageKey
        self.defaultValue = defaultValue
    }

    /// The stored choice, or `defaultValue` when nothing valid is stored.
    public func stored(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultValue
    }

    /// Persists `value` so the next `stored(in:)` reads it back.
    public func store(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: storageKey)
    }

    /// Flip the image left to right, the way a viewfinder normally behaves.
    public static let mirrorVideo = BoolSetting(storageKey: "MirrorVideo", defaultValue: true)

    /// Record the microphone alongside the video.
    public static let recordAudio = BoolSetting(storageKey: "RecordAudio", defaultValue: true)
}
