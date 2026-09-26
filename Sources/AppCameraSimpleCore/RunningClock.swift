import Foundation

/// Elapsed time across start/pause cycles; paused spans are not counted.
public struct RunningClock {
    private var accumulated: TimeInterval = 0
    private var startedAt: Date?

    public init() {}

    /// A no-op while already running.
    public mutating func start(now: Date = Date()) {
        if startedAt == nil { startedAt = now }
    }

    public mutating func pause(now: Date = Date()) {
        guard let startedAt else { return }
        accumulated += now.timeIntervalSince(startedAt)
        self.startedAt = nil
    }

    public mutating func reset() {
        accumulated = 0
        startedAt = nil
    }

    public func elapsed(now: Date = Date()) -> TimeInterval {
        accumulated + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }
}
