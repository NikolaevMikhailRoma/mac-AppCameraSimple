import Foundation
@preconcurrency import AVFoundation
import AppCameraSimpleCore

/// Settings dictionaries aren't provably `Sendable`; built on the main actor,
/// only read on the sample queue.
struct WriterConfig: @unchecked Sendable {
    let url: URL
    let fileType: AVFileType
    let video: [String: Any]?
    let audio: [String: Any]?
}

enum RecorderError: Error {
    /// Stopped before a single frame was written.
    case noData
    case writeFailed
}

/// The writing half of `Recorder`. Touched only on its sample queue, which makes
/// the unchecked conformance safe. Not an actor: hopping off the synchronous
/// delegate callback would let buffers overtake each other.
final class SampleWriter: @unchecked Sendable {
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var timeline = PauseTimeline()

    func begin(_ config: WriterConfig) {
        reset()
        try? FileManager.default.removeItem(at: config.url)
        guard let writer = try? AVAssetWriter(outputURL: config.url, fileType: config.fileType) else { return }

        // AVAssetWriterInput throws an uncatchable ObjC exception on settings
        // without both dimensions; no writer fails the take cleanly instead.
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
        timeline.setPaused(value)
    }

    func append(_ sampleBuffer: CMSampleBuffer, isVideo: Bool) {
        guard let writer, writer.status == .writing,
              CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let placement = timeline.place(
            pts: pts,
            duration: CMSampleBufferGetDuration(sampleBuffer),
            isVideo: isVideo,
            isBlank: { Self.isBlank(sampleBuffer) }
        ) else { return }

        if placement.startsSession {
            writer.startSession(atSourceTime: pts)
        }

        guard let input = isVideo ? videoInput : audioInput,
              input.isReadyForMoreMediaData,
              let buffer = Self.retimed(sampleBuffer, by: placement.shift) else { return }
        input.append(buffer)
    }

    func finish(_ completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        guard let writer, timeline.hasStarted, writer.status == .writing else {
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

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        timeline = PauseTimeline()
    }

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
        return FrameUniformity.isUniform(UnsafeRawBufferPointer(start: base, count: rowBytes * height),
                                         rowBytes: rowBytes, height: height)
    }

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
