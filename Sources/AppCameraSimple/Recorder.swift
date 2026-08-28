import Foundation
@preconcurrency import AVFoundation
import AppCameraSimpleCore

/// Wraps `AVCaptureMovieFileOutput` to support pause/resume while producing a
/// single output file. Each running span is recorded natively as a temp `.mov`
/// segment; on `stop()` a lone segment is moved (same container) or remuxed
/// (passthrough) into place, and multiple segments are stitched together
/// (passthrough) into one file of the chosen container.
@MainActor
final class Recorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    enum State { case idle, recording, paused }

    /// `AVFileType` for a stored `MovieFormat` choice.
    private static func fileType(for format: MovieFormat) -> AVFileType {
        switch format {
        case .mov: return .mov
        case .mp4: return .mp4
        }
    }

    enum RecorderError: Error { case noData, exportUnavailable }

    /// What to do once the segment currently being written finishes.
    private enum Pending { case none, resume, finalize }

    /// Temp segments are always written in the native container.
    private static let segmentExtension = "mov"

    private(set) var state: State = .idle
    private var format: MovieFormat = .fallback
    private let movieOutput = AVCaptureMovieFileOutput()

    private var segments: [URL] = []
    private var segmentError: Error?
    private var pendingSegmentFinish = false
    private var pending: Pending = .none

    private var destinationFolder: URL?
    private var finalName = ""
    private var completion: ((Result<URL, Error>) -> Void)?

    /// Called when a stitch/export step begins (only when pauses occurred).
    var onProcessing: (() -> Void)?

    /// Adds the movie output to the session and forces H.264 so both `.mov` and
    /// `.mp4` files stay broadly portable. Call inside its configuration block.
    func configure(session: AVCaptureSession) {
        guard session.canAddOutput(movieOutput) else { return }
        session.addOutput(movieOutput)
        if let connection = movieOutput.connection(with: .video) {
            movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: connection)
        }
    }

    var isActive: Bool { state != .idle }

    /// Begins recording. The final file name is decided now so the UI can show
    /// it immediately; the return value is that name (e.g. `20260828_143000.mov`).
    @discardableResult
    func start(folder: URL) -> String {
        segments.removeAll()
        segmentError = nil
        pending = .none
        destinationFolder = folder
        format = MovieFormat.stored()
        finalName = Filenames.captureName(ext: format.fileExtension)
        state = .recording
        startSegment()
        return finalName
    }

    func pause() {
        guard state == .recording else { return }
        state = .paused
        pending = .none
        movieOutput.stopRecording()
    }

    func resume() {
        guard state == .paused else { return }
        state = .recording
        if pendingSegmentFinish {
            pending = .resume
        } else {
            startSegment()
        }
    }

    /// Finishes recording. `completion` is invoked (on the main actor) with the
    /// final file URL once every segment has been written and merged.
    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        guard state != .idle else { return }
        self.completion = completion
        switch state {
        case .recording:
            pending = .finalize
            movieOutput.stopRecording()
        case .paused:
            if pendingSegmentFinish {
                pending = .finalize
            } else {
                assembleOutput()
            }
        case .idle:
            break
        }
        state = .idle
    }

    private func startSegment() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("segment-\(segments.count)-\(UUID().uuidString).\(Recorder.segmentExtension)")
        pendingSegmentFinish = true
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        // A "successful" stop still reports an error carrying this success key.
        let succeeded = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        Task { @MainActor [weak self] in
            self?.segmentFinished(outputFileURL, succeeded: succeeded, error: error)
        }
    }

    private func segmentFinished(_ url: URL, succeeded: Bool, error: Error?) {
        pendingSegmentFinish = false
        if succeeded {
            segments.append(url)
        } else {
            segmentError = error
        }
        switch pending {
        case .none:
            break
        case .resume:
            pending = .none
            if state == .recording { startSegment() }
        case .finalize:
            pending = .none
            assembleOutput()
        }
    }

    private func assembleOutput() {
        guard let folder = destinationFolder else { return }
        let dest = folder.appendingPathComponent(finalName)

        if segments.isEmpty {
            finish(.failure(segmentError ?? RecorderError.noData))
            return
        }
        let fileType = Recorder.fileType(for: format)

        if segments.count == 1 {
            let only = segments[0]
            segments.removeAll()

            // Fast path: same container as the temp segment — just move it.
            if format.fileExtension == Recorder.segmentExtension {
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: only, to: dest)
                    finish(.success(dest))
                } catch {
                    try? FileManager.default.removeItem(at: only)
                    finish(.failure(error))
                }
                return
            }

            // Different container — remux (passthrough, no re-encode).
            onProcessing?()
            Task { @MainActor [weak self] in
                do {
                    try await Recorder.stitch(segments: [only], to: dest, fileType: fileType)
                    self?.finish(.success(dest))
                } catch {
                    self?.finish(.failure(error))
                }
                try? FileManager.default.removeItem(at: only)
            }
            return
        }

        onProcessing?()
        let segs = segments
        Task { @MainActor [weak self] in
            do {
                try await Recorder.stitch(segments: segs, to: dest, fileType: fileType)
                self?.finish(.success(dest))
            } catch {
                self?.finish(.failure(error))
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        for segment in segments {
            try? FileManager.default.removeItem(at: segment)
        }
        segments.removeAll()
        segmentError = nil
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    /// Concatenates `segments` (one or more) into `dest` using a passthrough
    /// export — no re-encode, so a single segment is just remuxed to `fileType`.
    /// Runs off the main actor; every parameter crossing back is `Sendable`.
    private nonisolated static func stitch(segments: [URL],
                                           to dest: URL,
                                           fileType: AVFileType) async throws {
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero
        for (index, segment) in segments.enumerated() {
            let asset = AVURLAsset(url: segment)
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)
            if let source = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack?.insertTimeRange(range, of: source, at: cursor)
                if index == 0 {
                    videoTrack?.preferredTransform = try await source.load(.preferredTransform)
                }
            }
            if let source = try await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(range, of: source, at: cursor)
            }
            cursor = CMTimeAdd(cursor, duration)
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw RecorderError.exportUnavailable
        }
        try? FileManager.default.removeItem(at: dest)
        try await export.export(to: dest, as: fileType)
    }
}
