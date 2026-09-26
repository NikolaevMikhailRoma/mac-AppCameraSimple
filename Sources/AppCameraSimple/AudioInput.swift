@preconcurrency import AVFoundation

/// The microphone joins the session only for a take, so the orange mic
/// indicator stays off while previewing and taking photos.
@MainActor
final class AudioInput {
    private let session: AVCaptureSession
    private var input: AVCaptureDeviceInput?

    init(session: AVCaptureSession) {
        self.session = session
    }

    /// Waits for the permission answer first: until it is granted the device
    /// vends silence. Denied or missing just means a silent take.
    func attach(then: @escaping @MainActor (_ attached: Bool) -> Void) {
        guard input == nil else { return then(true) }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            addInput()
            then(input != nil)
        case .notDetermined:
            AudioInput.requestAccess { [weak self] in
                self?.addInput()
                then(self?.input != nil)
            }
        default:
            then(false)
        }
    }

    /// Must be `nonisolated`: `requestAccess` answers on an XPC queue, and an
    /// inline closure here would inherit the main actor and trap when TCC replies.
    private nonisolated static func requestAccess(then: @escaping @MainActor () -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in then() }
        }
    }

    func detach() {
        guard let input else { return }
        self.input = nil
        session.beginConfiguration()
        session.removeInput(input)
        session.commitConfiguration()
    }

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
