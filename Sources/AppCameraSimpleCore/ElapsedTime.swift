import Foundation

/// Formats a recording duration as `mm:ss` (and `h:mm:ss` once past an hour).
public enum ElapsedTime {
    public static func string(from seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let secs = total % 60
        let mins = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }
}
