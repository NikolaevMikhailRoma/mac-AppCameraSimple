import AppKit
@preconcurrency import AVFoundation
import AppCameraSimpleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AVCapturePhotoCaptureDelegate {
    private var window: NSWindow!
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let recorder = Recorder()

    private var photoButton: NSButton!
    private var recordButton: NSButton!
    private var pauseButton: NSButton!
    private var infoLabel: NSTextField!

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

    /// Full URL for a new capture in the user's chosen save folder.
    private func captureURL(ext: String) -> URL {
        photoFolder.resolvedFolder().appendingPathComponent(Filenames.captureName(ext: ext))
    }

    private func symbolImage(_ name: String, pointSize: CGFloat = 22) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: name)!.withSymbolConfiguration(config)!
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu(target: self)
        configureSession()

        recorder.onProcessing = { [weak self] in
            self?.infoLabel.stringValue = "Processing…"
        }

        let previewView = CameraPreviewView(session: session)

        photoButton = NSButton(image: symbolImage("camera.fill"), target: self, action: #selector(takePhoto))
        photoButton.bezelStyle = .regularSquare
        photoButton.isBordered = false
        photoButton.imagePosition = .imageOnly

        recordButton = NSButton(image: symbolImage("record.circle"), target: self, action: #selector(toggleRecording))
        recordButton.bezelStyle = .regularSquare
        recordButton.isBordered = false
        recordButton.imagePosition = .imageOnly
        setRecordIcon(recording: false)

        pauseButton = NSButton(image: symbolImage("pause.circle"), target: self, action: #selector(togglePause))
        pauseButton.bezelStyle = .regularSquare
        pauseButton.isBordered = false
        pauseButton.imagePosition = .imageOnly
        pauseButton.isHidden = true

        photoButton.contentTintColor = .white
        recordButton.contentTintColor = .white
        pauseButton.contentTintColor = .white

        infoLabel = NSTextField(labelWithString: "")
        infoLabel.alignment = .center
        infoLabel.textColor = .white
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.alphaValue = 0.9

        let stack = NSStackView(views: [photoButton, recordButton, pauseButton])
        stack.orientation = .horizontal
        stack.spacing = 24
        stack.alignment = .centerY

        // The bar sits directly on top of the video. A faint bottom-up scrim
        // keeps the white icons legible over bright footage without adding a
        // solid strip of chrome.
        let settingsButton = NSButton(
            image: symbolImage("gearshape", pointSize: 16),
            target: self,
            action: #selector(showSettings)
        )
        settingsButton.bezelStyle = .regularSquare
        settingsButton.isBordered = false
        settingsButton.imagePosition = .imageOnly
        settingsButton.contentTintColor = .white

        let buttonBar = ScrimView()
        buttonBar.addSubview(stack)
        buttonBar.addSubview(infoLabel)
        buttonBar.addSubview(settingsButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: buttonBar.centerXAnchor),
            stack.topAnchor.constraint(equalTo: buttonBar.topAnchor, constant: 10),
            settingsButton.trailingAnchor.constraint(equalTo: buttonBar.trailingAnchor, constant: -12),
            settingsButton.centerYAnchor.constraint(equalTo: stack.centerYAnchor),
            infoLabel.centerXAnchor.constraint(equalTo: buttonBar.centerXAnchor),
            infoLabel.bottomAnchor.constraint(equalTo: buttonBar.bottomAnchor, constant: -8),
        ])

        // 16:9 to match the camera's native aspect ratio; the button bar floats
        // over the preview, so the window is exactly the video size.
        let previewWidth: CGFloat = 960
        let previewHeight = previewWidth * 9 / 16
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: previewWidth, height: previewHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appName
        window.contentView = makeRootView(previewView: previewView, buttonBar: buttonBar)
        window.center()
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if recorder.isActive {
            recorder.stop { _ in }
        }
        session.stopRunning()
        photoFolder.stopAccessing()
        videoFolder.stopAccessing()
        return true
    }

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

    @objc func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                photoFolder: photoFolder,
                videoFolder: videoFolder
            )
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func takePhoto() {
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = (error == nil) ? photo.fileDataRepresentation() : nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let data else { self.infoLabel.stringValue = "Photo failed"; return }
            let url = self.captureURL(ext: "jpg")
            do {
                try data.write(to: url)
                self.lastName = url.lastPathComponent
                self.refreshInfo()
            } catch {
                self.infoLabel.stringValue = "Photo failed"
            }
        }
    }

    @objc private func toggleRecording() {
        if recorder.isActive {
            stopRecordingTimer()
            setRecordIcon(recording: false)
            recorder.stop { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let url):
                    self.lastName = url.lastPathComponent
                    self.refreshInfo()
                case .failure:
                    self.infoLabel.stringValue = "Recording failed"
                }
                self.syncPauseButton()
            }
        } else {
            lastName = recorder.start(folder: videoFolder.resolvedFolder())
            refreshInfo()
            clock.reset()
            clock.start()
            setRecordIcon(recording: true)
            startRecordingTimer()
        }
        syncPauseButton()
    }

    @objc private func togglePause() {
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

    /// Shows/hides the pause button and swaps its icon for the current state.
    private func syncPauseButton() {
        pauseButton.isHidden = !recorder.isActive
        let paused = recorder.state == .paused
        pauseButton.image = symbolImage(paused ? "play.circle" : "pause.circle")
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
        switch recorder.state {
        case .idle:
            infoLabel.stringValue = lastName
        case .recording:
            infoLabel.stringValue = "\(lastName)  ·  \(ElapsedTime.string(from: clock.elapsed()))"
        case .paused:
            infoLabel.stringValue = "\(lastName)  ·  \(ElapsedTime.string(from: clock.elapsed()))  ·  paused"
        }
    }

    private func setRecordIcon(recording: Bool) {
        let name = recording ? "stop.circle.fill" : "record.circle"
        let image = symbolImage(name)
        if recording {
            image.isTemplate = false
            recordButton.contentTintColor = .systemRed
        } else {
            recordButton.contentTintColor = .white
        }
        recordButton.image = image
    }
}
