import AppKit

@MainActor
func symbolImage(_ name: String, pointSize: CGFloat = 22) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    let image = NSImage(systemSymbolName: name, accessibilityDescription: name)
    return image?.withSymbolConfiguration(config) ?? image ?? NSImage()
}

@MainActor
func iconButton(symbol: String, pointSize: CGFloat = 22, target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(image: symbolImage(symbol, pointSize: pointSize), target: target, action: action)
    button.bezelStyle = .regularSquare
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.contentTintColor = .white
    return button
}
