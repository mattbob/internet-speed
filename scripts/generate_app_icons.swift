import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)

let iconSpecs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func renderIcon(size: Int) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create bitmap for \(size)")
    }

    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let size = CGFloat(size)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.22
    NSGraphicsContext.current?.imageInterpolation = .high

    let gradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.11, green: 0.53, blue: 0.96, alpha: 1),
            NSColor(calibratedRed: 0.07, green: 0.34, blue: 0.86, alpha: 1),
        ]
    )!
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    gradient.draw(in: path, angle: 90)

    let circleRect = rect.insetBy(dx: size * 0.13, dy: size * 0.13)
    NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
    NSBezierPath(ovalIn: circleRect).fill()

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .bold)
    let symbol = NSImage(
        systemSymbolName: "arrow.left.arrow.right",
        accessibilityDescription: nil
    )!.withSymbolConfiguration(symbolConfig)!
    let symbolSize = NSSize(width: size * 0.50, height: size * 0.50)
    let symbolRect = NSRect(
        x: (size - symbolSize.width) / 2,
        y: (size - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )

    NSColor.white.set()
    symbol.draw(
        in: symbolRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for spec in iconSpecs {
    let bitmap = renderIcon(size: spec.size)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode \(spec.name)")
    }

    try pngData.write(to: outputDirectory.appendingPathComponent(spec.name))
}
