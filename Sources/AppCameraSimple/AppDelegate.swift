import AppKit
@preconcurrency import AVFoundation
import AppCameraSimpleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var bar: ControlBar!
    private var previewView: CameraPreviewView!

    private let session = AVCaptureSession()
    private lazy var photo = PhotoCapture(folder: photoFolder)
    private lazy var recording = RecordingController(session: session, folder: videoFolder)

    /// The active recording's file name, or the last saved file's name.
    private var lastName = ""

    private let photoFolder = SaveFolderStore(
        keyPrefix: "SaveFolder",
        defaultFolder: SaveFolderStore.picturesSubfolder(appName: appName)
    )
    private let videoFolder = SaveFolderStore(
        keyPrefix: "VideoSaveFolder",
        defaultFolder: SaveFolderStore.picturesSubfolder(appName: appName)
    )
    private var settingsWindowController: SettingsWindowController?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu(target: self)
        configureSession()

        bar = ControlBar()
        bar.onPhoto = { [weak self] in self?.photo.capture() }
        bar.onRecord = { [weak self] in self?.recording.toggle() }
        bar.onPause = { [weak self] in self?.recording.togglePause() }
        bar.onSettings = { [weak self] in self?.showSettings() }

        photo.onFinished = { [weak self] result in
            self?.showSaved(result, failure: "Photo failed")
        }
        recording.onTakeStarted = { [weak self] name in self?.lastName = name }
        recording.onUpdate = { [weak self] in self?.syncBar() }
        recording.onTakeFinished = { [weak self] result in
            self?.showSaved(result, failure: "Recording failed")
        }

        previewView = CameraPreviewView(session: session)
        window = makeWindow(previewView: previewView)
        window.makeKeyAndOrderFront(nil)
        applyMirroring()

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A file is only playable once the writer has closed it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recording.hasOpenFile else { return .terminateNow }
        recording.finish {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        bar.showInfo("Finishing recording…")
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.stopRunning()
    }

    // MARK: - Setup

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        photo.configure(session: session)
        recording.configure(session: session)
        session.commitConfiguration()
    }

    /// All three connections: preview, photo and video.
    private func applyMirroring() {
        let mirrored = Settings.mirrorVideo.stored()
        previewView.previewLayer.connection?.setMirrored(mirrored)
        photo.setMirrored(mirrored)
        recording.setMirrored(mirrored)
    }

    /// 16:9, the camera's native aspect ratio.
    private func makeWindow(previewView: NSView) -> NSWindow {
        let width: CGFloat = 960
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: width * 9 / 16),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appName
        window.contentView = makeRootView(previewView: previewView, controlBar: bar)
        window.center()
        return window
    }

    @objc func showSettings() {
        let controller = settingsWindowController ?? SettingsWindowController(
            photoFolder: photoFolder,
            videoFolder: videoFolder
        )
        controller.onMirrorChanged = { [weak self] in self?.applyMirroring() }
        settingsWindowController = controller
        controller.refresh()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Status

    private func showSaved(_ result: Result<URL, Error>, failure: String) {
        switch result {
        case .success(let url):
            lastName = url.lastPathComponent
            refreshInfo()
        case .failure:
            bar.showInfo(failure)
        }
    }

    private func syncBar() {
        bar.show(recording.state)
        refreshInfo()
    }

    private func refreshInfo() {
        bar.showInfo(StatusLine.text(name: lastName, state: recording.state, elapsed: recording.elapsed))
    }
}
