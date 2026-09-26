import Foundation

public enum Filenames {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    /// E.g. `20260828_150102.jpg`.
    public static func captureName(ext: String, date: Date = Date()) -> String {
        "\(formatter.string(from: date)).\(ext)"
    }
}
