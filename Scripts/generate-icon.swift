import AppKit

// Renders an SF Symbol on a rounded, colored square background and exports the
// standard macOS iconset PNG sizes. Usage: swift generate-icon.swift <output .iconset dir>

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("usage: generate-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(1)
}

let outputDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func renderIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = CGFloat(size) * 0.22
    let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.70, alpha: 1),
    ])
    gradient?.draw(in: backgroundPath, angle: -90)

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.5, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor.white.set()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let origin = NSPoint(x: (CGFloat(size) - tinted.size.width) / 2, y: (CGFloat(size) - tinted.size.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

for (name, size) in sizes {
    let image = renderIcon(size: size)
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to render \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = outputDir.appendingPathComponent("\(name).png")
    try png.write(to: url)
}

print("Wrote \(sizes.count) icon sizes to \(outputDir.path)")
