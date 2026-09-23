import Foundation
@preconcurrency import AVFoundation

/// Everything `AVAssetWriter` needs to open a file. AVFoundation hands back
/// plain dictionaries Swift cannot prove `Sendable`; they are built once on the
/// main actor and only ever read on the sample queue.
struct WriterConfig: @unchecked Sendable {
    let url: URL
    let fileType: AVFileType
    let video: [String: Any]?
    /// `nil` when no microphone is in the session, so no audio track is created.
    let audio: [String: Any]?
}

enum RecorderError: Error {
    /// Stopped before a single frame was written.
    case noData
    case writeFailed
}

/// The writing half of `Recorder`.
///
/// Every member is touched only on the recorder's sample queue — the same queue
/// the capture callbacks arrive on — which is what makes the unchecked
/// conformance safe. An actor cannot take its place: the delegate callback is
/// synchronous, and hopping off it would let buffers overtake each other.
final class SampleWriter: @unchecked Sendable {
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?

    /// Set once the writer has a session, which only the first video frame starts.
    private var started = false
    private var paused = false

    /// Total paused time removed from the timeline so far.
    private var offset = CMTime.zero
    /// Source timestamp and length of the last frame written, used to measure
    /// the next gap and to land the resumed frame one frame after it.
    private var lastVideoPTS = CMTime.invalid
    private var lastVideoDuration = CMTime.invalid
    /// Set on resume until a video frame arrives to measure the gap against.
    private var awaitingResume = false
    /// Timestamp of the first frame offered, which bounds the blank-frame skip.
    private var firstSeenPTS = CMTime.invalid

    /// How long after the start blank frames are still skipped. Measured on the
    /// built-in camera: a reconfigured session emits three of them and recovers
    /// in about 200 ms, so half a second is comfortable margin.
    private static let blankWindow = CMTime(value: 1, timescale: 2)

    // MARK: - Transport, all on the sample queue

    func begin(_ config: WriterConfig) {
        reset()
        try? FileManager.default.removeItem(at: config.url)
        guard let writer = try? AVAssetWriter(outputURL: config.url, fileType: config.fileType) else { return }

        // Guarded rather than trusted: AVAssetWriterInput throws an uncatchable
        // ObjC exception on settings without both dimensions. No writer means
        // the take fails cleanly instead of taking the app down.
        guard let videoSettings = config.video,
              videoSettings[AVVideoWidthKey] != nil, videoSettings[AVVideoHeightKey] != nil else { return }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = true
        if writer.canAdd(video) { writer.add(video); videoInput = video }

        if let settings = config.audio {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            audio.expectsMediaDataInRealTime = true
            if writer.canAdd(audio) { writer.add(audio); audioInput = audio }
        }

        guard writer.startWriting() else { return }
        self.writer = writer
    }

    func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value
        // On resume, wait for a video frame before deciding how much to skip.
        if !value { awaitingResume = started }
    }

    func append(_ sampleBuffer: CMSampleBuffer, isVideo: Bool) {
        guard let writer, writer.status == .writing, !paused,
              CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }

        // The session starts on the first video frame; audio before it is dropped
        // so the two tracks begin together.
        if !started {
            guard isVideo else { return }
            if !firstSeenPTS.isValid { firstSeenPTS = pts }
            // A capture session rebuilds its graph on every commitConfiguration —
            // which attaching the microphone does, right before a take — and the
            // camera emits a few synthetic blank frames while it comes back.
            // Opening the file on one of those is what leaves a player showing a
            // black poster image. The skip is time-boxed, so a genuinely flat
            // scene still starts a recording rather than blocking it forever.
            if Self.isBlank(sampleBuffer), CMTimeSubtract(pts, firstSeenPTS) < Self.blankWindow {
                return
            }
            writer.startSession(atSourceTime: pts)
            started = true
        }

        // Close the gap a pause left behind. Measured on video, then applied to
        // both tracks so they stay in step; audio in between is dropped.
        if awaitingResume {
            guard isVideo else { return }
            if lastVideoPTS.isValid {
                // One frame past the last one written, not level with it: an
                // exact tie is not a monotonic timeline, and the writer rejects
                // the whole file at finishWriting with a bare -11800.
                let frame = (lastVideoDuration.isValid && lastVideoDuration > .zero)
                    ? lastVideoDuration
                    : CMTime(value: 1, timescale: 30)
                offset = CMTimeAdd(offset, CMTimeSubtract(pts, CMTimeAdd(lastVideoPTS, frame)))
            }
            awaitingResume = false
        }

        if isVideo {
            lastVideoPTS = pts
            lastVideoDuration = CMSampleBufferGetDuration(sampleBuffer)
        }

        guard let input = isVideo ? videoInput : audioInput,
              input.isReadyForMoreMediaData,
              let buffer = Self.retimed(sampleBuffer, by: offset) else { return }
        input.append(buffer)
    }

    /// Closes the file and reports it. `completion` runs on the sample queue.
    func finish(_ completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        guard let writer, started, writer.status == .writing else {
            let error = self.writer?.error ?? RecorderError.noData
            if let url = self.writer?.outputURL { try? FileManager.default.removeItem(at: url) }
            reset()
            completion(.failure(error))
            return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        let url = writer.outputURL
        reset()
        writer.finishWriting {
            if writer.status == .completed {
                completion(.success(url))
            } else {
                try? FileManager.default.removeItem(at: url)
                completion(.failure(writer.error ?? RecorderError.writeFailed))
            }
        }
    }

    // MARK: - Helpers

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        started = false
        paused = false
        awaitingResume = false
        offset = .zero
        lastVideoPTS = .invalid
        lastVideoDuration = .invalid
        firstSeenPTS = .invalid
    }

    /// True when every sampled byte of the frame is identical. Real camera
    /// output never is — even a covered lens carries sensor noise — so this only
    /// matches the placeholder frames a restarting capture graph emits.
    private static func isBlank(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return false }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }

        let planar = CVPixelBufferIsPlanar(pixels)
        guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(pixels, 0)
                                : CVPixelBufferGetBaseAddress(pixels) else { return false }
        let rowBytes = planar ? CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
                              : CVPixelBufferGetBytesPerRow(pixels)
        let height = planar ? CVPixelBufferGetHeightOfPlane(pixels, 0)
                            : CVPixelBufferGetHeight(pixels)
        guard rowBytes > 0, height > 0 else { return false }

        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let reference = bytes[0]
        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: rowBytes, by: 8) where bytes[y * rowBytes + x] != reference {
                return false
            }
        }
        return true
    }

    /// A copy of `sampleBuffer` with `offset` taken off every timestamp, so the
    /// written timeline has no hole where a pause was.
    private static func retimed(_ sampleBuffer: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        guard offset != .zero else { return sampleBuffer }

        var count: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0,
                                                     arrayToFill: nil, entriesNeededOut: &count) == noErr else { return nil }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count,
                                                     arrayToFill: &timings, entriesNeededOut: nil) == noErr else { return nil }
        for index in 0..<count {
            timings[index].presentationTimeStamp = CMTimeSubtract(timings[index].presentationTimeStamp, offset)
            if timings[index].decodeTimeStamp.isValid {
                timings[index].decodeTimeStamp = CMTimeSubtract(timings[index].decodeTimeStamp, offset)
            }
        }

        var copy: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                                    sampleBuffer: sampleBuffer,
                                                    sampleTimingEntryCount: count,
                                                    sampleTimingArray: &timings,
                                                    sampleBufferOut: &copy) == noErr else { return nil }
        return copy
    }
}
