import CoreMedia

/// Per sample: drop it, open the writer's session on it, or shift it back to
/// close the gap a pause left.
public struct PauseTimeline {
    public struct Placement: Equatable {
        public let startsSession: Bool
        public let shift: CMTime
    }

    /// The built-in camera emits blank frames for about 200 ms after a reconfigure.
    public static let blankWindow = CMTime(value: 1, timescale: 2)

    public static let fallbackFrameDuration = CMTime(value: 1, timescale: 30)

    public private(set) var hasStarted = false
    private var paused = false

    /// Total paused time removed so far.
    private var offset = CMTime.zero
    private var lastVideoPTS = CMTime.invalid
    private var lastVideoDuration = CMTime.invalid
    private var awaitingResume = false
    private var firstSeenPTS = CMTime.invalid

    public init() {}

    public mutating func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value
        if !value { awaitingResume = hasStarted }
    }

    /// `nil` drops the sample. `isBlank` is only asked before the session starts.
    public mutating func place(pts: CMTime, duration: CMTime, isVideo: Bool,
                               isBlank: () -> Bool) -> Placement? {
        guard pts.isValid, !paused else { return nil }

        // Start on video, so both tracks begin together.
        var startsSession = false
        if !hasStarted {
            guard isVideo else { return nil }
            if !firstSeenPTS.isValid { firstSeenPTS = pts }
            // Attaching the mic reconfigures the session, and the camera emits
            // blank frames meanwhile; opening on one gives a black poster image.
            // Time-boxed, so a genuinely flat scene still starts.
            if CMTimeSubtract(pts, firstSeenPTS) < Self.blankWindow, isBlank() {
                return nil
            }
            hasStarted = true
            startsSession = true
        }

        // Measure the pause gap on video, apply it to both tracks.
        if awaitingResume {
            guard isVideo else { return nil }
            if lastVideoPTS.isValid {
                // One frame past the last one, not level with it: a tie makes
                // finishWriting reject the whole file with -11800.
                let frame = (lastVideoDuration.isValid && lastVideoDuration > .zero)
                    ? lastVideoDuration
                    : Self.fallbackFrameDuration
                offset = CMTimeAdd(offset, CMTimeSubtract(pts, CMTimeAdd(lastVideoPTS, frame)))
            }
            awaitingResume = false
        }

        if isVideo {
            lastVideoPTS = pts
            lastVideoDuration = duration
        }
        return Placement(startsSession: startsSession, shift: offset)
    }
}

public enum FrameUniformity {
    /// Real camera output never is uniform — even a covered lens has sensor
    /// noise — so this only matches synthetic frames.
    public static func isUniform(_ bytes: UnsafeRawBufferPointer, rowBytes: Int, height: Int,
                                 step: Int = 8) -> Bool {
        guard rowBytes > 0, height > 0, bytes.count >= rowBytes * height else { return false }
        let reference = bytes[0]
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: rowBytes, by: step) where bytes[y * rowBytes + x] != reference {
                return false
            }
        }
        return true
    }
}
