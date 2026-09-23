import Foundation
@preconcurrency import AVFoundation
import AppCameraSimpleCore

extension MovieFormat {
    /// Container type handed to the writer.
    var avFileType: AVFileType {
        switch self {
        case .mov: return .mov
        case .mp4: return .mp4
        }
    }
}

/// Records the capture session straight to its final file with `AVAssetWriter`,
/// fed by the session's video and audio data outputs.
///
/// The alternative, `AVCaptureMovieFileOutput`, is simpler but cannot mirror:
/// it never flips pixels, it writes the mirror as a display matrix on the video
/// track. AVFoundation reads that back correctly, but ffmpeg-based players (VLC
/// among them) collapse the reflection into a plain `rotation=-180` and play the
/// clip upside down. A video data output mirrors the pixel buffers themselves,
/// so the file needs no orientation metadata at all and looks the same
/// everywhere — see `MovieFormat` before adding another container.
///
/// Writing frames directly also makes pause/resume a matter of subtracting the
/// paused gap from each timestamp, so there are no temp segments to stitch.
@MainActor
final class Recorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum State { case idle, recording, paused }

    private(set) var state: State = .idle

    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private weak var session: AVCaptureSession?

    /// Capture callbacks arrive here, and every writer touch happens here too.
    private nonisolated let queue = DispatchQueue(label: "AppCameraSimple.samples")
    private nonisolated let writer = SampleWriter()

    var isActive: Bool { state != .idle }

    /// Adds the data outputs to the session. Call inside its configuration block.
    func configure(session: AVCaptureSession) {
        self.session = session
        if session.canAddOutput(videoOutput) {
            // Recording wants every frame, not just the ones that arrive on time.
            videoOutput.alwaysDiscardsLateVideoFrames = false
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
        }
        if session.canAddOutput(audioOutput) {
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(audioOutput)
        }
    }

    /// Mirrors the frames as they are captured, which is what puts the flip in
    /// the pixels. Ignored mid-take: the change would land partway through the
    /// clip instead of applying to the whole of it.
    func setMirrored(_ mirrored: Bool) {
        guard state == .idle else { return }
        videoOutput.connection(with: .video)?.setMirrored(mirrored)
    }

    // MARK: - Transport

    /// Begins recording into `folder` and returns the file name it will have.
    @discardableResult
    func start(folder: URL) -> String {
        let format = MovieFormat.stored()
        let name = Filenames.captureName(ext: format.fileExtension)
        let fileType = format.avFileType

        setMirrored(BoolSetting.mirrorVideo.stored())

        let config = WriterConfig(
            url: folder.appendingPathComponent(name),
            fileType: fileType,
            video: videoSettings(for: fileType),
            // Only write an audio track when a microphone actually joined the
            // session, so a video-only take gets no empty track.
            audio: hasAudioInput
                ? audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: fileType)
                : nil
        )

        state = .recording
        queue.async { [writer] in writer.begin(config) }
        return name
    }

    func pause() {
        guard state == .recording else { return }
        state = .paused
        queue.async { [writer] in writer.setPaused(true) }
    }

    func resume() {
        guard state == .paused else { return }
        state = .recording
        queue.async { [writer] in writer.setPaused(false) }
    }

    /// Finishes the file. `completion` runs on the main actor once it is closed.
    func stop(completion: @escaping @MainActor (Result<URL, Error>) -> Void) {
        guard state != .idle else { return }
        state = .idle
        queue.async { [writer] in
            writer.finish { result in
                Task { @MainActor in completion(result) }
            }
        }
    }

    /// Compression settings for the written video track.
    ///
    /// It has to be `recommendedVideoSettingsForAssetWriter(writingTo:)`: the
    /// `forVideoCodecType:` sibling returns only the codec on macOS, and an
    /// input built from that throws `NSInvalidArgumentException: Missing
    /// required key AVVideoHeightKey` — an uncatchable crash.
    private func videoSettings(for fileType: AVFileType) -> [String: Any]? {
        guard let recommended = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: fileType),
              let width = recommended[AVVideoWidthKey], let height = recommended[AVVideoHeightKey] else {
            return nil
        }
        // Force H.264. The system may recommend HEVC, which is smaller but which
        // plenty of players outside Apple's world will not open; the recommended
        // compression properties are dropped with it, as they are codec-specific.
        guard recommended[AVVideoCodecKey] as? String == AVVideoCodecType.h264.rawValue else {
            return [AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height]
        }
        return recommended
    }

    /// True when the session currently holds a microphone.
    private var hasAudioInput: Bool {
        session?.inputs.contains {
            ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true
        } ?? false
    }

    // MARK: - Capture callbacks

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        writer.append(sampleBuffer, isVideo: output is AVCaptureVideoDataOutput)
    }
}
