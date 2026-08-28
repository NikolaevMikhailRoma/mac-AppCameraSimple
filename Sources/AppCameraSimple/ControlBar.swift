import AppKit

/// The floating bar over the video: photo / record / pause buttons, a settings
/// gear, and the single status line. Owns its widgets and reports taps through
/// closures, so the app delegate never touches individual controls.
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

    /// The status line under the buttons: file name, elapsed time, errors.
    func showInfo(_ text: String) {
        infoLabel.stringValue = text
    }

    /// Swaps the record button between "start" and a red "stop".
    func setRecording(_ recording: Bool) {
        let image = symbolImage(recording ? "stop.circle.fill" : "record.circle")
        if recording { image.isTemplate = false }
        recordButton.contentTintColor = recording ? .systemRed : .white
        recordButton.image = image
    }

    /// Shows the pause button only while a recording is active, with the icon
    /// for the action the next tap performs.
    func setPause(visible: Bool, paused: Bool) {
        pauseButton.isHidden = !visible
        pauseButton.image = symbolImage(paused ? "play.circle" : "pause.circle")
    }

    @objc private func photoTapped() { onPhoto?() }
    @objc private func recordTapped() { onRecord?() }
    @objc private func pauseTapped() { onPause?() }
    @objc private func settingsTapped() { onSettings?() }
}
