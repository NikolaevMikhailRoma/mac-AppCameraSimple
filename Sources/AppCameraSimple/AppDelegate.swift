import AppKit
@preconcurrency import AVFoundation
import AppCameraSimpleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AVCapturePhotoCaptureDelegate {
    private var window: NSWindow!
    private var bar: ControlBar!
    private var previewView: CameraPreviewView!

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let recorder = Recorder()
    private lazy var audio = AudioInput(session: session)

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

    private var recordingTimer: Timer?
    private var clock = RunningClock()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu(target: self)
        configureSession()

        bar = ControlBar()
        bar.onPhoto = { [weak self] in self?.takePhoto() }
        bar.onRecord = { [weak self] in self?.toggleRecording() }
        bar.onPause = { [weak self] in self?.togglePause() }
        bar.onSettings = { [weak self] in self?.showSettings() }

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

    /// Quitting mid-recording has to wait: the file is only playable once the
    /// writer has closed it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recorder.isActive else { return .terminateNow }
        stopRecordingTimer()
        bar.showInfo("Finishing recording…")
        recorder.stop { _ in
            NSApp.reply(toApplicationShouldTerminate: true)
        }
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
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        recorder.configure(session: session)
        session.commitConfiguration()
    }

    /// Applies the mirror setting to all three connections. The preview flips
    /// live; the photo and video outputs flip the pixels themselves, so nothing
    /// depends on a player honouring orientation metadata. The recorder ignores
    /// this mid-take, keeping a clip mirrored the same way from end to end.
    private func applyMirroring() {
        let mirrored = BoolSetting.mirrorVideo.stored()
        previewView.previewLayer.connection?.setMirrored(mirrored)
        photoOutput.connection(with: .video)?.setMirrored(mirrored)
        recorder.setMirrored(mirrored)
    }

    /// 16:9 to match the camera's native aspect ratio; the control bar floats
    /// over the preview, so the window is exactly the video size.
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

    // MARK: - Photo

    private func takePhoto() {
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = (error == nil) ? photo.fileDataRepresentation() : nil
        Task { @MainActor [weak self] in
            self?.savePhoto(data)
        }
    }

    private func savePhoto(_ data: Data?) {
        guard let data else { return bar.showInfo("Photo failed") }
        let url = photoFolder.resolvedFolder()
            .appendingPathComponent(Filenames.captureName(ext: "jpg"))
        do {
            try data.write(to: url)
            lastName = url.lastPathComponent
            refreshInfo()
        } catch {
            bar.showInfo("Photo failed")
        }
    }

    // MARK: - Recording

    private func toggleRecording() {
        if recorder.isActive {
            stopRecordingTimer()
            bar.setRecording(false)
            recorder.stop { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let url):
                    self.lastName = url.lastPathComponent
                    self.refreshInfo()
                case .failure:
                    self.bar.showInfo("Recording failed")
                }
                // The file is closed by now, so the microphone can go back.
                self.audio.detach()
                self.syncPauseButton()
            }
            syncPauseButton()
        } else if BoolSetting.recordAudio.stored() {
            audio.attach { [weak self] in self?.beginRecording() }
        } else {
            beginRecording()
        }
    }

    /// The mic is claimed before this runs, so the clip has sound from its very
    /// first frame. Pause and resume keep it; it is released once the whole take
    /// is finished.
    private func beginRecording() {
        lastName = recorder.start(folder: videoFolder.resolvedFolder())
        clock.reset()
        clock.start()
        bar.setRecording(true)
        startRecordingTimer()
        syncPauseButton()
    }

    private func togglePause() {
        switch recorder.state {
        case .recording:
            recorder.pause()
            clock.pause()
            stopRecordingTimer()
            refreshInfo()
        case .paused:
            recorder.resume()
            clock.start()
            startRecordingTimer()
        case .idle:
            break
        }
        syncPauseButton()
    }

    private func syncPauseButton() {
        bar.setPause(visible: recorder.isActive, paused: recorder.state == .paused)
    }

    private func startRecordingTimer() {
        refreshInfo()
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshInfo() }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    /// The single bottom line: file name while idle, plus elapsed time and a
    /// pause marker while a recording is in progress.
    private func refreshInfo() {
        let elapsed = ElapsedTime.string(from: clock.elapsed())
        switch recorder.state {
        case .idle:
            bar.showInfo(lastName)
        case .recording:
            bar.showInfo("\(lastName)  ·  \(elapsed)")
        case .paused:
            bar.showInfo("\(lastName)  ·  \(elapsed)  ·  paused")
        }
    }
}
