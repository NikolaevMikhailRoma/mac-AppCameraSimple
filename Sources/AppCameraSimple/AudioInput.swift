@preconcurrency import AVFoundation

/// Owns the microphone's place in the capture session.
///
/// The mic is joined only while a recording runs, so previewing and taking
/// photos never claim it — the orange microphone indicator in the menu bar stays
/// off until the user actually records, and other apps keep the device in the
/// meantime.
@MainActor
final class AudioInput {
    private let session: AVCaptureSession
    private var input: AVCaptureDeviceInput?

    init(session: AVCaptureSession) {
        self.session = session
    }

    /// Joins the microphone to the session, then runs `then`.
    ///
    /// The first call asks for access and waits for the answer: a capture device
    /// vends silent samples until permission is granted, so recording before the
    /// user has replied would quietly produce a silent file. A denied or missing
    /// microphone is not an error either — the recording simply has no sound —
    /// so `then` runs either way.
    func attach(then: @escaping @MainActor () -> Void) {
        guard input == nil else { return then() }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            addInput()
            then()
        case .notDetermined:
            AudioInput.requestAccess { [weak self] in
                self?.addInput()
                then()
            }
        default:
            then()
        }
    }

    /// Asks for microphone access, then resumes on the main actor.
    ///
    /// This has to be `nonisolated`. `requestAccess` answers on an XPC queue,
    /// and its handler is not annotated for strict concurrency, so a closure
    /// written inline inside this `@MainActor` class silently inherits the main
    /// actor: it compiles, then traps on an "already on the main queue"
    /// assertion the moment TCC replies. Taking the hop explicitly is the fix.
    private nonisolated static func requestAccess(then: @escaping @MainActor () -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in then() }
        }
    }

    /// Releases the microphone. Does nothing when none is attached.
    func detach() {
        guard let input else { return }
        self.input = nil
        session.beginConfiguration()
        session.removeInput(input)
        session.commitConfiguration()
    }

    /// Inputs may be added to a running session; the preview keeps going, since
    /// nothing about the video connection or the preset changes.
    private func addInput() {
        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        self.input = input
    }
}
