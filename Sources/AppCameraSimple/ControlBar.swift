import AppKit
import AppCameraSimpleCore

/// The floating bar over the video: buttons, settings gear and status line.
@MainActor
final class ControlBar: ScrimView {
    var onPhoto: (() -> Void)?
    var onRecord: (() -> Void)?
    var onPause: (() -> Void)?
    var onSettings: (() -> Void)?

    private var photoButton: NSButton!
    private var recordButton: NSButton!
    private var pauseButton: NSButton!
    private var settingsButton: NSButton!
    private let infoLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        photoButton = iconButton(symbol: "camera.fill", target: self, action: #selector(photoTapped))
        recordButton = iconButton(symbol: "record.circle", target: self, action: #selector(recordTapped))
        pauseButton = iconButton(symbol: "pause.circle", target: self, action: #selector(pauseTapped))
        pauseButton.isHidden = true
        settingsButton = iconButton(
            symbol: "gearshape",
            pointSize: 16,
            target: self,
            action: #selector(settingsTapped)
        )

        infoLabel.alignment = .center
        infoLabel.textColor = .white
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.alphaValue = 0.9

        let stack = NSStackView(views: [photoButton, recordButton, pauseButton])
        stack.orientation = .horizontal
        stack.spacing = 24
        stack.alignment = .centerY

        for view in [stack, infoLabel, settingsButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            settingsButton.centerYAnchor.constraint(equalTo: stack.centerYAnchor),
            infoLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            infoLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func showInfo(_ text: String) {
        infoLabel.stringValue = text
    }

    /// Record is disabled while a take is starting or finishing.
    func show(_ state: TakeState) {
        let active = state == .recording || state == .paused
        let recordImage = symbolImage(active ? "stop.circle.fill" : "record.circle")
        if active { recordImage.isTemplate = false }
        recordButton.image = recordImage
        recordButton.contentTintColor = active ? .systemRed : .white
        recordButton.isEnabled = state == .idle || active
        pauseButton.isHidden = !active
        pauseButton.image = symbolImage(state == .paused ? "play.circle" : "pause.circle")
    }

    @objc private func photoTapped() { onPhoto?() }
    @objc private func recordTapped() { onRecord?() }
    @objc private func pauseTapped() { onPause?() }
    @objc private func settingsTapped() { onSettings?() }
}
