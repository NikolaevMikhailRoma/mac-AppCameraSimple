import Foundation
@preconcurrency import AVFoundation
import AppCameraSimpleCore

/// Drives a take: microphone, `Recorder`, elapsed-time clock.
///
/// Record is ignored while `.starting` or `.finishing`: a tap during the mic
/// prompt would start a second take over the first, and one right after a stop
/// would have the old take's cleanup pull the mic out of the new one.
@MainActor
final class RecordingController {
    /// On every state change and once a second while recording.
    var onUpdate: (() -> Void)?
    var onTakeStarted: ((_ name: String) -> Void)?
    /// Fires once `state` is back to `.idle`.
    var onTakeFinished: ((Result<URL, Error>) -> Void)?

    private(set) var state: TakeState = .idle

    private let recorder = Recorder()
    private let audio: AudioInput
    private let folder: SaveFolderStore

    private var clock = RunningClock()
    private var timer: Timer?
    private var finishWaiters: [@MainActor () -> Void] = []

    init(session: AVCaptureSession, folder: SaveFolderStore) {
        audio = AudioInput(session: session)
        self.folder = folder
    }

    func configure(session: AVCaptureSession) {
        recorder.configure(session: session)
    }

    func setMirrored(_ mirrored: Bool) {
        recorder.setMirrored(mirrored)
    }

    var elapsed: TimeInterval { clock.elapsed() }

    var hasOpenFile: Bool {
        switch state {
        case .recording, .paused, .finishing: return true
        case .idle, .starting: return false
        }
    }

    // MARK: - Buttons

    func toggle() {
        switch state {
        case .idle: start()
        case .recording, .paused: stop()
        case .starting, .finishing: break
        }
    }

    func togglePause() {
        switch state {
        case .recording:
            recorder.pause()
            set(.paused)
        case .paused:
            recorder.resume()
            set(.recording)
        case .idle, .starting, .finishing:
            break
        }
    }

    /// Closes any open file, then runs `then`.
    func finish(then: @escaping @MainActor () -> Void) {
        guard hasOpenFile else { return then() }
        finishWaiters.append(then)
        if state != .finishing { stop() }
    }

    // MARK: - Take

    private func start() {
        guard Settings.recordAudio.stored() else { return begin(withAudio: false) }
        set(.starting)
        audio.attach { [weak self] attached in self?.begin(withAudio: attached) }
    }

    /// Runs after the mic is in, so `Recorder.start` mirrors the reconfigured session.
    private func begin(withAudio: Bool) {
        let name = recorder.start(
            folder: folder.resolvedFolder(),
            format: Settings.movieFormat.stored(),
            mirrored: Settings.mirrorVideo.stored(),
            withAudio: withAudio
        )
        onTakeStarted?(name)
        clock.reset()
        set(.recording)
    }

    private func stop() {
        set(.finishing)
        recorder.stop { [weak self] result in
            guard let self else { return }
            self.audio.detach()
            self.set(.idle)
            self.onTakeFinished?(result)
            let waiters = self.finishWaiters
            self.finishWaiters = []
            waiters.forEach { $0() }
        }
    }

    // MARK: - State

    private func set(_ newState: TakeState) {
        state = newState
        timer?.invalidate()
        timer = nil
        if newState == .recording {
            clock.start()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.onUpdate?() }
            }
        } else {
            clock.pause()
        }
        onUpdate?()
    }
}
