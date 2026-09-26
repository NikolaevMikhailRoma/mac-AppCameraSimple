import AppKit
import AppCameraSimpleCore

@MainActor
final class SettingsWindowController: NSWindowController {
    /// The only setting that must reach the live preview immediately.
    var onMirrorChanged: (() -> Void)?

    private let photoFolder: SaveFolderStore
    private let videoFolder: SaveFolderStore

    private let photoValue = NSTextField(labelWithString: "")
    private let videoValue = NSTextField(labelWithString: "")
    private let formatPopUp = NSPopUpButton()
    private let mirrorCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let audioCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    /// Fits the tallest tab, so switching tabs never resizes the window.
    private static let size = NSSize(width: 480, height: 220)

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
        tabs.addTabViewItem(tab("Picture", rows: [("Save to", folderControl(photoValue, #selector(changePhotoFolder)))]))
        tabs.addTabViewItem(tab("Video", rows: [
            ("Save to", folderControl(videoValue, #selector(changeVideoFolder))),
            ("Format", formatPopUp),
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
        let grid = NSGridView(views: rows.map { [caption($0.0), $0.1] })
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

    @objc private func changeMirror() {
        Settings.mirrorVideo.store(mirrorCheckbox.state == .on)
        onMirrorChanged?()
    }

    @objc private func changeAudio() {
        Settings.recordAudio.store(audioCheckbox.state == .on)
    }
}
