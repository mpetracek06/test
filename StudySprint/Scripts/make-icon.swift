// Renders the StudySprint app icon (gradient squircle + bolt) into an .iconset folder.
// Usage: swift Scripts/make-icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data? {
    let size = CGFloat(px)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: ~10% margin, continuous-corner squircle.
    let inset = size * 0.1
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.29, green: 0.23, blue: 0.86, alpha: 1),
        NSColor(calibratedRed: 0.62, green: 0.25, blue: 0.86, alpha: 1),
        NSColor(calibratedRed: 0.96, green: 0.36, blue: 0.62, alpha: 1),
    ])
    gradient?.draw(in: path, angle: -50)

    // Soft highlight
    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    NSColor.white.withAlphaComponent(0.12).setFill()
    NSBezierPath(ovalIn: NSRect(x: rect.minX - rect.width * 0.2, y: rect.midY, width: rect.width * 1.4, height: rect.height)).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Bolt glyph
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .bold)
    if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: bolt.size, flipped: false) { r in
            bolt.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let s = tinted.size
        tinted.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        if let data = render(base * scale) {
            try data.write(to: out.appendingPathComponent(name))
        }
    }
}
print("Wrote \(out.path)")
