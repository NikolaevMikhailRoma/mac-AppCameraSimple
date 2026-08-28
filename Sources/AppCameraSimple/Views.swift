import AppKit
@preconcurrency import AVFoundation

/// Display name, taken from the bundle when packaged as a .app.
let appName = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "AppCameraSimple"

/// An SF Symbol sized for the control bar. Falls back to an empty image rather
/// than trapping if the system ever stops vending the symbol.
@MainActor
func symbolImage(_ name: String, pointSize: CGFloat = 22) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    let image = NSImage(systemSymbolName: name, accessibilityDescription: name)
    return image?.withSymbolConfiguration(config) ?? image ?? NSImage()
}

/// Borderless white icon button as used across the control bar.
@MainActor
func iconButton(symbol: String, pointSize: CGFloat = 22, target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(image: symbolImage(symbol, pointSize: pointSize), target: target, action: action)
    button.bezelStyle = .regularSquare
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.contentTintColor = .white
    return button
}

extension NSView {
    /// Pins this view to `other`'s edges, optionally inset on every side.
    @MainActor
    func pin(to other: NSView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: other.topAnchor, constant: inset),
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -inset),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -inset),
        ])
    }
}

/// Layer-backed view that hosts the live camera preview.
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

/// A transparent overlay with a subtle bottom-up dark gradient, used behind the
/// control buttons so they stay readable on top of the live video.
class ScrimView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradient.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.45).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }
}

/// The camera preview fills the whole window; the control bar is overlaid on
/// top of it at the bottom, so there is no separate strip of window chrome.
@MainActor
func makeRootView(previewView: NSView, controlBar: NSView) -> NSView {
    let root = NSView()
    root.addSubview(previewView)
    root.addSubview(controlBar)
    previewView.pin(to: root)

    controlBar.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        controlBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        controlBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        controlBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        controlBar.heightAnchor.constraint(equalToConstant: 74),
    ])

    return root
}
