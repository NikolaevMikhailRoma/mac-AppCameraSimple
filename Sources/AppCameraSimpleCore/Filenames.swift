import Foundation

/// Pure helpers for building capture file names. Kept free of AppKit so they
/// can be unit-tested in isolation.
public enum Filenames {
    /// `yyyyMMdd_HHmmss` stamp used as the base name for every capture.
    public static func timestamp(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }

    /// Full capture file name for the given extension, e.g. `20260828_150102.jpg`.
    public static func captureName(ext: String, date: Date = Date()) -> String {
        "\(timestamp(for: date)).\(ext)"
    }
}
