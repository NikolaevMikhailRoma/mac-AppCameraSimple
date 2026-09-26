import Foundation
@preconcurrency import AVFoundation
import AppCameraSimpleCore

extension MovieFormat {
    var avFileType: AVFileType {
        switch self {
        case .mov: return .mov
        case .mp4: return .mp4
        }
    }
}

/// Records with `AVAssetWriter` fed by video and audio data outputs.
///
/// Not `AVCaptureMovieFileOutput`: it writes the mirror as a display matrix on
/// the track, which ffmpeg-based players (VLC) read as `rotation=-180` and play
/// upside down. A video data output mirrors the pixel buffers themselves, so
/// the file carries no orientation metadata at all.
@MainActor
final class Recorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum State { case idle, recording, paused }

    private(set) var state: State = .idle

    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    /// Capture callbacks and every writer touch happen here.
    private nonisolated let queue = DispatchQueue(label: "AppCameraSimple.samples")
    private nonisolated let writer = SampleWriter()

    func configure(session: AVCaptureSession) {
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = false
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
        }
        if session.canAddOutput(audioOutput) {
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(audioOutput)
        }
    }

    /// Ignored mid-take, so a clip is mirrored the same way from end to end.
    func setMirrored(_ mirrored: Bool) {
        guard state == .idle else { return }
        videoOutput.connection(with: .video)?.setMirrored(mirrored)
    }

    // MARK: - Transport

    /// Returns the file name. Call only after the microphone has joined the
    /// session: attaching it reconfigures the session, so the mirror is applied
    /// here, after that.
    @discardableResult
    func start(folder: URL, format: MovieFormat, mirrored: Bool, withAudio: Bool) -> String {
        let name = Filenames.captureName(ext: format.fileExtension)
        let fileType = format.avFileType

        setMirrored(mirrored)

        let config = WriterConfig(
            url: folder.appendingPathComponent(name),
            fileType: fileType,
            video: videoSettings(for: fileType),
            audio: withAudio
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

    func stop(completion: @escaping @MainActor (Result<URL, Error>) -> Void) {
        guard state != .idle else { return }
        state = .idle
        queue.async { [writer] in
            writer.finish { result in
                Task { @MainActor in completion(result) }
            }
        }
    }

    /// Not `recommendedVideoSettings(forVideoCodecType:)`: on macOS it returns
    /// only the codec, and an input built from that crashes on the missing
    /// `AVVideoHeightKey`.
    private func videoSettings(for fileType: AVFileType) -> [String: Any]? {
        guard let recommended = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: fileType),
              let width = recommended[AVVideoWidthKey], let height = recommended[AVVideoHeightKey] else {
            return nil
        }
        // Force H.264: many players outside Apple's world won't open HEVC. The
        // recommended compression properties are codec-specific, so they go too.
        guard recommended[AVVideoCodecKey] as? String == AVVideoCodecType.h264.rawValue else {
            return [AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height]
        }
        return recommended
    }

    // MARK: - Capture callbacks

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        writer.append(sampleBuffer, isVideo: output is AVCaptureVideoDataOutput)
    }
}
