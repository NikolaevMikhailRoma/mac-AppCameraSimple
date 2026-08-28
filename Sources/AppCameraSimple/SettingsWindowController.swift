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
        formatPopUp.selectItem(withTitle: MovieFormat.stored().rawValue.uppercased())
    }

    private func makeContentView() -> NSView {
        for field in [photoValue, videoValue] {
            field.lineBreakMode = .byTruncatingHead
            field.textColor = .secondaryLabelColor
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        formatPopUp.addItems(withTitles: MovieFormat.allCases.map { $0.rawValue.uppercased() })
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
        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
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

    private func pickFolder(for store: SaveFolderStore) {
        FolderPicker.present(startingAt: store.resolvedFolder()) { [weak self] url in
            guard let self else { return }
            store.setFolder(url)
            self.refresh()
        }
    }

    @objc private func changePhotoFolder() { pickFolder(for: photoFolder) }
    @objc private func changeVideoFolder() { pickFolder(for: videoFolder) }

    @objc private func changeFormat() {
        let raw = formatPopUp.titleOfSelectedItem?.lowercased() ?? MovieFormat.fallback.rawValue
        UserDefaults.standard.set(raw, forKey: MovieFormat.storageKey)
    }
}
