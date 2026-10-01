import AppKit
@preconcurrency import AVFoundation
import AppCameraSimpleCore

@MainActor
final class SettingsWindowController: NSWindowController {
    /// The only setting that must reach the live preview immediately.
    var onMirrorChanged: (() -> Void)?

    /// The camera's format: which video sizes it allows, and the size estimates.
    var camera: (() -> CameraFormat?)?

    private let photoFolder: SaveFolderStore
    private let videoFolder: SaveFolderStore

    private let photoValue = NSTextField(labelWithString: "")
    private let videoValue = NSTextField(labelWithString: "")
    private let formatPopUp = NSPopUpButton()
    private let videoSizePopUp = NSPopUpButton()
    private let videoEstimate = NSTextField(labelWithString: "")
    private let photoFormatPopUp = NSPopUpButton()
    private let qualityCaption = NSTextField(labelWithString: "Quality")
    private let qualitySlider = NSSlider(value: 0, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let qualityValue = NSTextField(labelWithString: "")
    private let scaleSlider = NSSlider(value: 1, minValue: PhotoScale.range.lowerBound,
                                       maxValue: PhotoScale.range.upperBound, target: nil, action: nil)
    private let scaleValue = NSTextField(labelWithString: "")
    private let photoEstimate = NSTextField(labelWithString: "")
    private let mirrorCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let audioCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    /// Fits the tallest tab, so switching tabs never resizes the window.
    private static let size = NSSize(width: 480, height: 260)

    init(photoFolder: SaveFolderStore, videoFolder: SaveFolderStore) {
        self.photoFolder = photoFolder
        self.videoFolder = videoFolder

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsWindowController.size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        super.init(window: window)

        window.contentView = makeContentView()
        window.center()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        for (label, store) in [(photoValue, photoFolder), (videoValue, videoFolder)] {
            let path = store.resolvedFolder().path
            label.stringValue = (path as NSString).abbreviatingWithTildeInPath
            label.toolTip = path
        }
        formatPopUp.selectItem(withTitle: Settings.movieFormat.stored().displayName)
        let photo = PhotoOptions.stored()
        photoFormatPopUp.selectItem(withTitle: photo.format.displayName)
        qualitySlider.doubleValue = photo.quality
        scaleSlider.doubleValue = photo.scale
        showPhotoOptions()
        showVideoSizes()
        mirrorCheckbox.state = Settings.mirrorVideo.stored() ? .on : .off
        audioCheckbox.state = Settings.recordAudio.stored() ? .on : .off
    }

    private func makeContentView() -> NSView {
        for field in [photoValue, videoValue] {
            field.lineBreakMode = .byTruncatingHead
            field.alignment = .right
            field.textColor = .secondaryLabelColor
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        formatPopUp.addItems(withTitles: MovieFormat.allCases.map(\.displayName))
        formatPopUp.target = self
        formatPopUp.action = #selector(changeFormat)

        photoFormatPopUp.addItems(withTitles: PhotoFormat.allCases.map(\.displayName))
        photoFormatPopUp.target = self
        photoFormatPopUp.action = #selector(changePhotoFormat)
        for (slider, action) in [(qualitySlider, #selector(changeQuality)), (scaleSlider, #selector(changeScale))] {
            slider.target = self
            slider.action = action
            slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        }
        for label in [qualityValue, scaleValue] {
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }
        photoEstimate.textColor = .secondaryLabelColor
        videoEstimate.textColor = .secondaryLabelColor
        videoSizePopUp.target = self
        videoSizePopUp.action = #selector(changeVideoSize)

        mirrorCheckbox.target = self
        mirrorCheckbox.action = #selector(changeMirror)
        audioCheckbox.target = self
        audioCheckbox.action = #selector(changeAudio)

        let applicationCaption = NSTextField(labelWithString: "APPLICATION")
        applicationCaption.textColor = .secondaryLabelColor
        let quit = NSButton(title: "Quit \(appName)", target: NSApp, action: #selector(NSApplication.terminate(_:)))

        let tabs = NSTabView()
        tabs.addTabViewItem(tab("General", rows: [("Mirror image", mirrorCheckbox)],
                                footer: [applicationCaption, quit]))
        tabs.addTabViewItem(tab("Picture", rows: [
            (caption("Save to"), folderControl(photoValue, #selector(changePhotoFolder))),
            (caption("Format"), photoFormatPopUp),
            (qualityCaption, row(qualitySlider, qualityValue)),
            (caption("Scale"), row(scaleSlider, scaleValue)),
            (caption("Size"), photoEstimate),
        ]))
        tabs.addTabViewItem(tab("Video", rows: [
            ("Save to", folderControl(videoValue, #selector(changeVideoFolder))),
            ("Format", formatPopUp),
            ("Size", row(videoEstimate, videoSizePopUp)),
            ("Record audio", audioCheckbox),
        ]))

        let container = NSView()
        container.addSubview(tabs)
        tabs.pin(to: container, inset: 16)
        return container
    }

    /// Captions on the left, controls pushed to the right, rows at the top;
    /// `footer` is centered below them.
    private func tab(_ label: String, rows: [(String, NSView)], footer: [NSView] = []) -> NSTabViewItem {
        tab(label, rows: rows.map { (caption($0.0), $0.1) }, footer: footer)
    }

    private func tab(_ label: String, rows: [(NSTextField, NSView)], footer: [NSView] = []) -> NSTabViewItem {
        let grid = NSGridView(views: rows.map { [$0.0, $0.1] })
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 1).xPlacement = .trailing
        grid.yPlacement = .center

        let stack = NSStackView(views: [grid] + footer)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(28, after: grid)

        let view = NSView()
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        let item = NSTabViewItem()
        item.label = label
        item.view = view
        return item
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return label
    }

    private func row(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.spacing = 8
        return stack
    }

    /// The folder path, truncated from the left, then its Change… button.
    private func folderControl(_ path: NSTextField, _ action: Selector) -> NSView {
        let stack = NSStackView(views: [path, changeButton(action)])
        stack.spacing = 8
        return stack
    }

    private func changeButton(_ action: Selector) -> NSButton {
        let button = NSButton(title: "Change…", target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func pickFolder(for store: SaveFolderStore, message: String) {
        FolderPicker.present(startingAt: store.resolvedFolder(), message: message) { [weak self] url in
            store.setFolder(url)
            self?.refresh()
        }
    }

    @objc private func changePhotoFolder() {
        pickFolder(for: photoFolder, message: "Choose a folder for saved photos")
    }

    @objc private func changeVideoFolder() {
        pickFolder(for: videoFolder, message: "Choose a folder for recorded videos")
    }

    @objc private func changeFormat() {
        Settings.movieFormat.store(MovieFormat.named(formatPopUp.titleOfSelectedItem) ?? Settings.movieFormat.defaultValue)
    }

    @objc private func changePhotoFormat() {
        Settings.photoFormat.store(PhotoFormat.named(photoFormatPopUp.titleOfSelectedItem) ?? Settings.photoFormat.defaultValue)
        showPhotoOptions()
        showVideoSizes()
    }

    /// In steps of 5%, finer than anyone can tell apart.
    @objc private func changeQuality() {
        qualitySlider.doubleValue = (qualitySlider.doubleValue * 20).rounded() / 20
        Settings.photoQuality.store(qualitySlider.doubleValue)
        showPhotoOptions()
        showVideoSizes()
    }

    /// Snaps while dragging, so the knob sticks to ½, ⅓, ¼ and the like.
    @objc private func changeScale() {
        scaleSlider.doubleValue = PhotoScale.snapped(scaleSlider.doubleValue)
        Settings.photoScale.store(scaleSlider.doubleValue)
        showPhotoOptions()
        showVideoSizes()
    }

    /// Greys out quality for PNG and updates the numbers beside the sliders.
    private func showPhotoOptions() {
        let options = PhotoOptions.stored()
        let hasQuality = options.format.hasQuality
        qualitySlider.isEnabled = hasQuality
        for label in [qualityCaption, qualityValue] {
            label.textColor = hasQuality ? .labelColor : .disabledControlTextColor
        }
        qualityValue.stringValue = "\(Int((options.quality * 100).rounded()))%"
        scaleValue.stringValue = String(format: "×%.2f", options.scale)

        guard let source = camera?() else {
            photoEstimate.stringValue = "—"
            return
        }
        let size = PhotoScale.size(width: source.width, height: source.height, scale: options.scale)
        let bytes = PhotoExport.estimatedBytes(width: source.width, height: source.height, options: options)
        photoEstimate.stringValue = "\(size.width) × \(size.height)  ·  ~\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
    }

    /// Only sizes the camera can fill are offered; one stored for a bigger
    /// camera shows, and records, as Original.
    private func showVideoSizes() {
        let format = camera?()
        let sizes = format.map(VideoSize.available(for:)) ?? [.original]
        videoSizePopUp.removeAllItems()
        videoSizePopUp.addItems(withTitles: sizes.map { size in
            guard size == .original, let format else { return size.displayName }
            return "Original (\(format.width)×\(format.height))"
        })
        let stored = Settings.videoSize.stored()
        videoSizePopUp.selectItem(at: sizes.firstIndex(of: stored) ?? 0)
        showVideoEstimate()
    }

    private func showVideoEstimate() {
        guard let format = camera?() else {
            videoEstimate.stringValue = ""
            return
        }
        let size = selectedVideoSize
        let frame = size.dimensions(for: format)
        let bytes = size.bytesPerSecond(for: format, withAudio: Settings.recordAudio.stored())
        videoEstimate.stringValue = size == .original
            ? "~\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))/s"
            : "\(frame.width) × \(frame.height)  ·  ~\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))/s"
    }

    /// The popup's first item carries the camera's size in its title.
    private var selectedVideoSize: VideoSize {
        videoSizePopUp.indexOfSelectedItem == 0 ? .original : VideoSize.named(videoSizePopUp.titleOfSelectedItem) ?? .original
    }

    @objc private func changeVideoSize() {
        Settings.videoSize.store(selectedVideoSize)
        showVideoEstimate()
    }

    @objc private func changeMirror() {
        Settings.mirrorVideo.store(mirrorCheckbox.state == .on)
        onMirrorChanged?()
    }

    /// Turning it on asks for the microphone right away. Once denied, the system
    /// never prompts again, so the user is sent to System Settings instead.
    @objc private func changeAudio() {
        guard audioCheckbox.state == .on else { return setRecordAudio(false) }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            setRecordAudio(true)
        case .notDetermined:
            AudioInput.requestAccess { [weak self] granted in self?.setRecordAudio(granted) }
        default:
            setRecordAudio(false)
            showMicrophoneDenied()
        }
    }

    private func setRecordAudio(_ on: Bool) {
        Settings.recordAudio.store(on)
        audioCheckbox.state = on ? .on : .off
        showVideoEstimate()
    }

    private func showMicrophoneDenied() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Microphone access is off"
        alert.informativeText = "Allow \(appName) in System Settings > Privacy & Security > Microphone, then turn Record audio on again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn,
                  let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
            NSWorkspace.shared.open(url)
        }
    }
}
