import AppKit
import AppCameraSimpleCore

/// Standard macOS Settings window: independent photo/video save folders and the
/// video container format, laid out in a captioned grid.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let photoFolder: SaveFolderStore
    private let videoFolder: SaveFolderStore

    private let photoValue = NSTextField(labelWithString: "")
    private let videoValue = NSTextField(labelWithString: "")
    private let formatPopUp = NSPopUpButton()

    init(photoFolder: SaveFolderStore, videoFolder: SaveFolderStore) {
        self.photoFolder = photoFolder
        self.videoFolder = videoFolder

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(appName) Settings"
        super.init(window: window)

        window.contentView = makeContentView()
        window.center()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Re-reads folders and the stored format into the controls.
    func refresh() {
        for (label, store) in [(photoValue, photoFolder), (videoValue, videoFolder)] {
            let path = store.resolvedFolder().path
            label.stringValue = (path as NSString).abbreviatingWithTildeInPath
            label.toolTip = path
        }
        formatPopUp.selectItem(withTitle: MovieFormat.stored().displayName)
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

        let grid = NSGridView(views: [
            [caption("Photos"), photoValue, changeButton(#selector(changePhotoFolder))],
            [caption("Videos"), videoValue, changeButton(#selector(changeVideoFolder))],
            [caption("Format"), formatPopUp],
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
        (MovieFormat.named(formatPopUp.titleOfSelectedItem) ?? .fallback).store()
    }
}
