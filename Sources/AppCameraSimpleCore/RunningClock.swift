import Foundation

/// Accumulates elapsed time across start/pause cycles: paused spans are not
/// counted. Used for the recording timer so pauses don't inflate the duration.
public struct RunningClock {
    private var accumulated: TimeInterval = 0
    private var startedAt: Date?

    public init() {}

    public var isRunning: Bool { startedAt != nil }

    /// Begins (or continues) counting. A no-op while already running.
    public mutating func start(now: Date = Date()) {
        if startedAt == nil { startedAt = now }
    }

    /// Freezes the count, folding the current run into the accumulated total.
    public mutating func pause(now: Date = Date()) {
        guard let startedAt else { return }
        accumulated += now.timeIntervalSince(startedAt)
        self.startedAt = nil
    }

    public mutating func reset() {
        accumulated = 0
        startedAt = nil
    }

    /// Total counted time: everything accumulated plus the current run, if any.
    public func elapsed(now: Date = Date()) -> TimeInterval {
        accumulated + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }
}
