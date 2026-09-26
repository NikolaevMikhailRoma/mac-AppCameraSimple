import AppKit

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
