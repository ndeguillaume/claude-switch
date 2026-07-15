// Génère Resources/AppIcon.icns. Usage : swift Scripts/generate_icon.swift
import AppKit

let projectRoot = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resourcesDir = projectRoot.appendingPathComponent("Scripts/Resources")
let iconsetDir = resourcesDir.appendingPathComponent("Scripts/Resources/AppIcon.iconset")

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.93, green: 0.60, blue: 0.45, alpha: 1),
    NSColor(calibratedRed: 0.76, green: 0.37, blue: 0.22, alpha: 1),
])!

func makeWhiteSymbol() -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: 460, weight: .semibold)
    guard
        let symbol = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
    else {
        fatalError("Symbole SF introuvable")
    }
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    return tinted
}

let whiteSymbol = makeWhiteSymbol()

func drawIcon(canvas: CGFloat) {
    let s = canvas / 1024

    let squircle = NSBezierPath(
        roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
        xRadius: 186 * s,
        yRadius: 186 * s
    )
    gradient.draw(in: squircle, angle: -90)

    // Léger reflet en haut pour le relief, fondu progressif pour éviter une ligne dure.
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    let sheen = NSGradient(
        starting: NSColor.white.withAlphaComponent(0.18),
        ending: NSColor.white.withAlphaComponent(0)
    )!
    sheen.draw(in: NSRect(x: 100 * s, y: 412 * s, width: 824 * s, height: 512 * s), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    let symbolWidth = 560 * s
    let symbolHeight = symbolWidth * (whiteSymbol.size.height / whiteSymbol.size.width)
    let symbolRect = NSRect(
        x: (canvas - symbolWidth) / 2,
        y: (canvas - symbolHeight) / 2,
        width: symbolWidth,
        height: symbolHeight
    )
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 18 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    whiteSymbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.current?.restoreGraphicsState()
}

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon(canvas: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
try? fileManager.removeItem(at: iconsetDir)
try fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in entries {
    let data = renderPNG(pixels: entry.pixels)
    try data.write(to: iconsetDir.appendingPathComponent("\(entry.name).png"))
}
try renderPNG(pixels: 256).write(to: resourcesDir.appendingPathComponent("preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns",
    iconsetDir.path,
    "-o", resourcesDir.appendingPathComponent("AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil a échoué (code \(iconutil.terminationStatus))")
}
try fileManager.removeItem(at: iconsetDir)

print("OK : \(resourcesDir.appendingPathComponent("AppIcon.icns").path)")
