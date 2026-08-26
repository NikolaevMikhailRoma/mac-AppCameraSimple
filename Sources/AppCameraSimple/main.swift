import AppKit
@preconcurrency import AVFoundation

private let appName = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "AppCameraSimple"

private let saveDirectory: URL = {
    let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
    let dir = pictures.appendingPathComponent(appName, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

private func timestampedURL(ext: String) -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    return saveDirectory.appendingPathComponent("\(formatter.string(from: Date())).\(ext)")
}

final class CameraPreviewView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

@MainActor
private func makeRootView(previewView: NSView, buttonBar: NSView) -> NSView {
    let root = NSView()
    root.addSubview(previewView)
    root.addSubview(buttonBar)

    previewView.translatesAutoresizingMaskIntoConstraints = false
    buttonBar.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
        previewView.topAnchor.constraint(equalTo: root.topAnchor),
        previewView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        previewView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        previewView.bottomAnchor.constraint(equalTo: buttonBar.topAnchor),

        buttonBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        buttonBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        buttonBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        buttonBar.heightAnchor.constraint(equalToConstant: 64),
    ])

    return root
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    private var window: NSWindow!
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    private var photoButton: NSButton!
    private var recordButton: NSButton!
    private var statusLabel: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureSession()

        let previewView = CameraPreviewView(session: session)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        photoButton = NSButton(image: NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Photo")!.withSymbolConfiguration(symbolConfig)!,
                                target: self, action: #selector(takePhoto))
        photoButton.bezelStyle = .regularSquare
        photoButton.isBordered = false
        photoButton.imagePosition = .imageOnly

        recordButton = NSButton(image: NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Record")!.withSymbolConfiguration(symbolConfig)!,
                                 target: self, action: #selector(toggleRecording))
        recordButton.bezelStyle = .regularSquare
        recordButton.isBordered = false
        recordButton.imagePosition = .imageOnly
        setRecordIcon(recording: false)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [photoButton, recordButton])
        stack.orientation = .horizontal
        stack.spacing = 24
        stack.alignment = .centerY

        let buttonBar = NSVisualEffectView()
        buttonBar.material = .hudWindow
        buttonBar.blendingMode = .withinWindow
        buttonBar.state = .active
        buttonBar.addSubview(stack)
        buttonBar.addSubview(statusLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: buttonBar.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor, constant: -8),
            statusLabel.centerXAnchor.constraint(equalTo: buttonBar.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: buttonBar.bottomAnchor, constant: -6),
        ])

        // 16:9 to match the camera's native aspect ratio, plus the button bar.
        let previewWidth: CGFloat = 960
        let previewHeight = previewWidth * 9 / 16
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: previewWidth, height: previewHeight + 64),
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
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        session.stopRunning()
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
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        session.commitConfiguration()
    }

    @objc private func takePhoto() {
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            Task { @MainActor [weak self] in self?.statusLabel.stringValue = "Photo failed" }
            return
        }
        let url = timestampedURL(ext: "jpg")
        do {
            try data.write(to: url)
            Task { @MainActor [weak self] in self?.statusLabel.stringValue = "Saved \(url.lastPathComponent)" }
        } catch {
            Task { @MainActor [weak self] in self?.statusLabel.stringValue = "Photo failed" }
        }
    }

    @objc private func toggleRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        } else {
            let url = timestampedURL(ext: "mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
            setRecordIcon(recording: true)
            statusLabel.stringValue = "Recording..."
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor [weak self] in
            self?.setRecordIcon(recording: false)
            self?.statusLabel.stringValue = error == nil ? "Saved \(outputFileURL.lastPathComponent)" : "Recording failed"
        }
    }

    private func setRecordIcon(recording: Bool) {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        let name = recording ? "stop.circle.fill" : "record.circle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Record")!.withSymbolConfiguration(symbolConfig)!
        if recording {
            image.isTemplate = false
            recordButton.contentTintColor = .systemRed
        } else {
            recordButton.contentTintColor = nil
        }
        recordButton.image = image
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
