import Foundation

public protocol SettingValue: Sendable {
    static func decode(_ object: Any?) -> Self?
    var encoded: Any { get }
}

extension Bool: SettingValue {
    /// Not `bool(forKey:)`: it reports `false` for a missing key.
    public static func decode(_ object: Any?) -> Bool? { object as? Bool }
    public var encoded: Any { self }
}

extension SettingValue where Self: RawRepresentable, RawValue == String {
    public static func decode(_ object: Any?) -> Self? { (object as? String).flatMap(Self.init(rawValue:)) }
    public var encoded: Any { rawValue }
}

/// Anything missing or unrecognized reads back as `defaultValue`.
public struct Setting<Value: SettingValue>: Sendable {
    public let storageKey: String
    public let defaultValue: Value

    public init(storageKey: String, defaultValue: Value) {
        self.storageKey = storageKey
        self.defaultValue = defaultValue
    }

    public func stored(in defaults: UserDefaults = .standard) -> Value {
        Value.decode(defaults.object(forKey: storageKey)) ?? defaultValue
    }

    public func store(_ value: Value, in defaults: UserDefaults = .standard) {
        defaults.set(value.encoded, forKey: storageKey)
    }
}

/// Storage keys are what earlier versions wrote; they must not change.
public enum Settings {
    public static let mirrorVideo = Setting(storageKey: "MirrorVideo", defaultValue: true)

    public static let recordAudio = Setting(storageKey: "RecordAudio", defaultValue: true)

    public static let movieFormat = Setting(storageKey: "MovieFormat", defaultValue: MovieFormat.mp4)
}
