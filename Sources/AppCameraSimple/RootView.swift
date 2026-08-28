import AppKit

/// The camera preview fills the whole window; the button bar is overlaid on
/// top of it at the bottom, so there is no separate strip of window chrome.
@MainActor
func makeRootView(previewView: NSView, buttonBar: NSView) -> NSView {
    let root = NSView()
    root.addSubview(previewView)
    root.addSubview(buttonBar)

    previewView.translatesAutoresizingMaskIntoConstraints = false
    buttonBar.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
        previewView.topAnchor.constraint(equalTo: root.topAnchor),
        previewView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        previewView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        previewView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

        buttonBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        buttonBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        buttonBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        buttonBar.heightAnchor.constraint(equalToConstant: 74),
    ])

    return root
}
