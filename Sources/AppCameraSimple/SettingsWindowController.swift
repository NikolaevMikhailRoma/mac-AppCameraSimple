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
    private let mirrorCheckbox = NSButton(checkboxWithTitle: "Mirror image", target: nil, action: nil)
    private let audioCheckbox = NSButton(checkboxWithTitle: "Record audio", target: nil, action: nil)

    private static let width: CGFloat = 460

    init(photoFolder: SaveFolderStore, videoFolder: SaveFolderStore) {
        self.photoFolder = photoFolder
        self.videoFolder = videoFolder

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsWindowController.width, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(appName) Settings"
        super.init(window: window)

        let content = makeContentView()
        window.contentView = content
        window.setContentSize(NSSize(width: SettingsWindowController.width, height: content.fittingSize.height))
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
            field.textColor = .secondaryLabelColor
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        formatPopUp.addItems(withTitles: MovieFormat.allCases.map(\.displayName))
        formatPopUp.target = self
        formatPopUp.action = #selector(changeFormat)

        mirrorCheckbox.target = self
        mirrorCheckbox.action = #selector(changeMirror)
        audioCheckbox.target = self
        audioCheckbox.action = #selector(changeAudio)

        let grid = NSGridView(views: [
            [caption("Photos"), photoValue, changeButton(#selector(changePhotoFolder))],
            [caption("Videos"), videoValue, changeButton(#selector(changeVideoFolder))],
            [caption("Format"), formatPopUp],
            [NSGridCell.emptyContentView, mirrorCheckbox],
            [NSGridCell.emptyContentView, audioCheckbox],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing

        let container = NSView()
        container.addSubview(grid)
        grid.pin(to: container, inset: 20)
        return container
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
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
