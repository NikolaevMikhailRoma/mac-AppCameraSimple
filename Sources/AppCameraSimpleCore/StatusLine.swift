import Foundation

public enum TakeState: Sendable {
    case idle
    /// Waiting for the mic, possibly on the permission prompt; no file yet.
    case starting
    case recording
    case paused
    /// Stopped; the file is still closing.
    case finishing
}

public enum StatusLine {
    public static func text(name: String, state: TakeState, elapsed: TimeInterval) -> String {
        let time = ElapsedTime.string(from: elapsed)
        switch state {
        case .idle, .starting:
            return name
        case .recording, .finishing:
            return "\(name)  ·  \(time)"
        case .paused:
            return "\(name)  ·  \(time)  ·  paused"
        }
    }
}
