import Foundation
@preconcurrency import AVFoundation
import AppCameraSimpleCore

extension MovieFormat {
    /// Container type handed to the exporter.
    var avFileType: AVFileType {
        switch self {
        case .mov: return .mov
        case .mp4: return .mp4
        }
    }
}

/// Wraps `AVCaptureMovieFileOutput` to support pause/resume while producing a
/// single output file. Each running span is recorded natively as a temp `.mov`
/// segment; on `stop()` a lone segment is moved (same container) or remuxed
/// (passthrough) into place, and multiple segments are stitched together
/// (passthrough) into one file of the chosen container.
@MainActor
final class Recorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    enum State { case idle, recording, paused }

    enum RecorderError: Error { case noData, exportUnavailable }

    /// Temp segments are always written in the native container.
    private static let segmentExtension = "mov"

    private(set) var state: State = .idle
    private var format: MovieFormat = .fallback
    private let movieOutput = AVCaptureMovieFileOutput()

    private var segments: [URL] = []
    private var segmentError: Error?

    /// Runs once the segment currently being written lands on disk. Pause and
    /// stop both have to wait for that callback before doing their real work.
    private var onSegmentFinished: (() -> Void)?

    private var destinationFolder: URL?
    private var finalName = ""
    private var completion: ((Result<URL, Error>) -> Void)?

    /// Called when a stitch/export step begins (only when a re-container or a
    /// merge is actually needed).
    var onProcessing: (() -> Void)?

    var isActive: Bool { state != .idle }

    /// True between `startRecording` and the delegate callback for that segment.
    /// Tracked by hand: `movieOutput.isRecording` flips to `false` as soon as
    /// `stopRecording()` is called, long before the file is actually on disk.
    private var isWritingSegment = false

    /// Adds the movie output to the session and forces H.264 so both `.mov` and
    /// `.mp4` files stay broadly portable. Call inside its configuration block.
    func configure(session: AVCaptureSession) {
        guard session.canAddOutput(movieOutput) else { return }
        session.addOutput(movieOutput)
        if let connection = movieOutput.connection(with: .video) {
            movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: connection)
        }
    }

    // MARK: - Transport

    /// Begins recording. The final file name is decided now so the UI can show
    /// it immediately; the return value is that name (e.g. `20260828_143000.mov`).
    @discardableResult
    func start(folder: URL) -> String {
        segments.removeAll()
        segmentError = nil
        onSegmentFinished = nil
        isWritingSegment = false
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
        onSegmentFinished = nil
        movieOutput.stopRecording()
    }

    func resume() {
        guard state == .paused else { return }
        state = .recording
        // If the paused segment is still being written, pick up in its callback.
        after(segmentLands: { [weak self] in
            guard let self, self.state == .recording else { return }
            self.startSegment()
        })
    }

    /// Finishes recording. `completion` is invoked (on the main actor) with the
    /// final file URL once every segment has been written and merged.
    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        guard state != .idle else { return }
        self.completion = completion
        let wasRecording = state == .recording
        state = .idle
        if wasRecording { movieOutput.stopRecording() }
        after(segmentLands: { [weak self] in self?.assembleOutput() })
    }

    /// Runs `work` as soon as no segment is in flight — right away when nothing
    /// is being written, otherwise from the recording delegate's callback.
    private func after(segmentLands work: @escaping () -> Void) {
        if isWritingSegment {
            onSegmentFinished = work
        } else {
            work()
        }
    }

    // MARK: - Segments

    private func startSegment() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("segment-\(segments.count)-\(UUID().uuidString).\(Recorder.segmentExtension)")
        isWritingSegment = true
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
        isWritingSegment = false
        if succeeded {
            segments.append(url)
        } else {
            segmentError = error
        }
        let work = onSegmentFinished
        onSegmentFinished = nil
        work?()
    }

    // MARK: - Assembly

    private func assembleOutput() {
        guard let folder = destinationFolder, !segments.isEmpty else {
            finish(.failure(segmentError ?? RecorderError.noData))
            return
        }
        let dest = folder.appendingPathComponent(finalName)

        // Fast path: a single segment already in the target container is just
        // moved into place — no export, no re-encode.
        if segments.count == 1, format.fileExtension == Recorder.segmentExtension {
            let only = segments.removeFirst()
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: only, to: dest)
                finish(.success(dest))
            } catch {
                segments = [only]
                finish(.failure(error))
            }
            return
        }

        // Otherwise export: one segment gets remuxed, several get concatenated.
        onProcessing?()
        let sources = segments
        let fileType = format.avFileType
        Task { @MainActor [weak self] in
            let result: Result<URL, Error>
            do {
                try await Recorder.stitch(segments: sources, to: dest, fileType: fileType)
                result = .success(dest)
            } catch {
                result = .failure(error)
            }
            self?.finish(result)
        }
    }

    /// Delivers the result and drops every temp segment left behind.
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
