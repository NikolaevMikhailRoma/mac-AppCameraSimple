import Foundation

/// Pure helper for building capture file names. Kept free of AppKit so it can
/// be unit-tested in isolation.
public enum Filenames {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    /// Capture file name for the given extension, e.g. `20260828_150102.jpg`.
    public static func captureName(ext: String, date: Date = Date()) -> String {
        "\(formatter.string(from: date)).\(ext)"
    }
}
