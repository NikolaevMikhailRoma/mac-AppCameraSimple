import XCTest
import CoreMedia
@testable import AppCameraSimpleCore

final class PauseTimelineTests: XCTestCase {
    private let frame = CMTime(value: 1, timescale: 30)

    /// `n` frames at 30 fps from zero.
    private func t(_ n: Int64) -> CMTime { CMTime(value: n, timescale: 30) }
    private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

    private func video(_ tl: inout PauseTimeline, _ pts: CMTime, duration: CMTime? = nil,
                       blank: Bool = false) -> PauseTimeline.Placement? {
        tl.place(pts: pts, duration: duration ?? frame, isVideo: true, isBlank: { blank })
    }

    private func audio(_ tl: inout PauseTimeline, _ pts: CMTime) -> PauseTimeline.Placement? {
        tl.place(pts: pts, duration: .invalid, isVideo: false, isBlank: { XCTFail("audio is never scanned"); return false })
    }

    func testAudioBeforeFirstVideoFrameIsDropped() {
        var tl = PauseTimeline()
        XCTAssertNil(audio(&tl, t(0)))
        XCTAssertFalse(tl.hasStarted)
    }

    func testFirstVideoFrameStartsSessionUnshifted() {
        var tl = PauseTimeline()
        XCTAssertEqual(video(&tl, t(5)), .init(startsSession: true, shift: .zero))
        XCTAssertEqual(video(&tl, t(6)), .init(startsSession: false, shift: .zero))
        XCTAssertEqual(audio(&tl, t(6)), .init(startsSession: false, shift: .zero))
    }

    func testInvalidTimestampIsDropped() {
        var tl = PauseTimeline()
        XCTAssertNil(video(&tl, .invalid))
        XCTAssertFalse(tl.hasStarted)
    }

    func testBlankFramesSkippedInsideWindow() {
        var tl = PauseTimeline()
        let start = seconds(10)
        XCTAssertNil(video(&tl, start, blank: true))
        XCTAssertNil(video(&tl, start + seconds(0.2), blank: true))
        XCTAssertEqual(video(&tl, start + seconds(0.25)), .init(startsSession: true, shift: .zero))
    }

    /// A genuinely flat scene must not block the recording forever.
    func testBlankFrameAfterWindowStillStartsSession() {
        var tl = PauseTimeline()
        let start = seconds(10)
        XCTAssertNil(video(&tl, start, blank: true))
        XCTAssertEqual(video(&tl, start + PauseTimeline.blankWindow, blank: true),
                       .init(startsSession: true, shift: .zero))
    }

    func testBlankCheckNotAskedOnceStarted() {
        var tl = PauseTimeline()
        _ = video(&tl, t(0))
        let placed = tl.place(pts: t(1), duration: frame, isVideo: true,
                              isBlank: { XCTFail("scanned after start"); return true })
        XCTAssertNotNil(placed)
    }

    func testPausedSamplesAreDropped() {
        var tl = PauseTimeline()
        _ = video(&tl, t(0))
        tl.setPaused(true)
        XCTAssertNil(video(&tl, t(1)))
        XCTAssertNil(audio(&tl, t(1)))
    }

    /// The resumed frame lands exactly one frame after the last one written:
    /// a tie would make the writer reject the file with -11800.
    func testResumeClosesGapToOneFrame() {
        var tl = PauseTimeline()
        _ = video(&tl, t(0))
        _ = video(&tl, t(10))          // last frame before the pause
        tl.setPaused(true)
        tl.setPaused(false)
        let resumed = video(&tl, t(100))
        XCTAssertEqual(resumed?.shift, t(89))
        XCTAssertEqual(CMTimeSubtract(t(100), resumed!.shift), t(11))
        // The shift carries over to the frames that follow.
        XCTAssertEqual(video(&tl, t(101))?.shift, t(89))
    }

    func testShiftsAccumulateAcrossPauses() {
        var tl = PauseTimeline()
        _ = video(&tl, t(0))
        tl.setPaused(true); tl.setPaused(false)
        _ = video(&tl, t(50))          // gap of 49 frames
        tl.setPaused(true); tl.setPaused(false)
        let second = video(&tl, t(80)) // gap of 29 more
        XCTAssertEqual(second?.shift, t(78))
        XCTAssertEqual(CMTimeSubtract(t(80), second!.shift), t(2))
    }

    func testUnknownFrameDurationFallsBackToThirtyFPS() {
        var tl = PauseTimeline()
        _ = video(&tl, seconds(1), duration: .invalid)
        tl.setPaused(true); tl.setPaused(false)
        let resumed = video(&tl, seconds(3))
        XCTAssertEqual(CMTimeSubtract(seconds(3), resumed!.shift),
                       seconds(1) + PauseTimeline.fallbackFrameDuration)
    }

    func testAudioBetweenResumeAndNextVideoFrameIsDropped() {
        var tl = PauseTimeline()
        _ = video(&tl, t(0))
        tl.setPaused(true); tl.setPaused(false)
        XCTAssertNil(audio(&tl, t(40)))
        _ = video(&tl, t(41))
        XCTAssertEqual(audio(&tl, t(42))?.shift, t(40))
    }

    /// Pausing before the first frame has nothing to close on resume.
    func testPauseBeforeStartAddsNoShift() {
        var tl = PauseTimeline()
        tl.setPaused(true); tl.setPaused(false)
        XCTAssertEqual(video(&tl, t(30)), .init(startsSession: true, shift: .zero))
    }

    func testRepeatedPauseCallsAreIdempotent() {
        var tl = PauseTimeline()
        _ = video(&tl, t(0))
        tl.setPaused(false)            // not paused: no-op, must not arm a resume
        XCTAssertEqual(video(&tl, t(1))?.shift, .zero)
    }
}

final class FrameUniformityTests: XCTestCase {
    private func check(_ bytes: [UInt8], rowBytes: Int, height: Int) -> Bool {
        bytes.withUnsafeBytes { FrameUniformity.isUniform($0, rowBytes: rowBytes, height: height) }
    }

    func testUniformBufferIsUniform() {
        XCTAssertTrue(check([UInt8](repeating: 16, count: 64 * 32), rowBytes: 64, height: 32))
    }

    func testNoisyBufferIsNot() {
        var bytes = [UInt8](repeating: 16, count: 64 * 32)
        bytes[8 * 64 + 16] = 17        // on the sampled grid
        XCTAssertFalse(check(bytes, rowBytes: 64, height: 32))
    }

    func testEmptyOrShortBufferIsNotUniform() {
        XCTAssertFalse(check([], rowBytes: 0, height: 0))
        XCTAssertFalse(check([1, 1, 1], rowBytes: 4, height: 1))
    }
}

final class StatusLineTests: XCTestCase {
    func testIdleAndStartingShowOnlyTheName() {
        XCTAssertEqual(StatusLine.text(name: "a.mp4", state: .idle, elapsed: 65), "a.mp4")
        XCTAssertEqual(StatusLine.text(name: "a.mp4", state: .starting, elapsed: 65), "a.mp4")
    }

    func testRecordingAndFinishingAddTheTime() {
        XCTAssertEqual(StatusLine.text(name: "a.mp4", state: .recording, elapsed: 65), "a.mp4  ·  01:05")
        XCTAssertEqual(StatusLine.text(name: "a.mp4", state: .finishing, elapsed: 65), "a.mp4  ·  01:05")
    }

    func testPausedIsMarked() {
        XCTAssertEqual(StatusLine.text(name: "a.mp4", state: .paused, elapsed: 5), "a.mp4  ·  00:05  ·  paused")
    }
}
