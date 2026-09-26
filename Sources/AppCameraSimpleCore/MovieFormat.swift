import Foundation

/// Output container for recorded video. Before adding one, see `Recorder` on
/// why the mirror must stay in the pixels.
public enum MovieFormat: String, CaseIterable, SettingValue {
    case mov
    case mp4

    public var fileExtension: String { rawValue }

    public var displayName: String { rawValue.uppercased() }

    public static func named(_ displayName: String?) -> MovieFormat? {
        displayName.flatMap { MovieFormat(rawValue: $0.lowercased()) }
    }
}
