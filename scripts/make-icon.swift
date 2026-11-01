// Draws Resources/AppIcon.icns. Run with: swift scripts/make-icon.swift
import AppKit

func draw(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    // macOS icon grid: an 824pt rounded square centered on the 1024pt canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor(srgbRed: 0.05, green: 0.46, blue: 0.43, alpha: 1).setFill()
    shape.fill()
    context.restoreGState()

    NSGradient(
        starting: NSColor(srgbRed: 0.13, green: 0.72, blue: 0.65, alpha: 1),
        ending: NSColor(srgbRed: 0.03, green: 0.31, blue: 0.36, alpha: 1)
    )!.draw(in: shape, angle: -90)

    let white = NSColor.white

    // Viewfinder corners: the region you drag out.
    white.withAlphaComponent(0.55).setStroke()
    let inset: CGFloat = 195, arm: CGFloat = 112
    let (low, high) = (inset, 1024 - inset)
    for (x, y, dx, dy) in [(low, high, 1.0, -1.0), (high, high, -1.0, -1.0), (low, low, 1.0, 1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        let corner = NSBezierPath()
        corner.lineWidth = 34
        corner.lineCapStyle = .round
        corner.lineJoinStyle = .round
        corner.move(to: CGPoint(x: x + dx * arm, y: y))
        corner.line(to: CGPoint(x: x, y: y))
        corner.line(to: CGPoint(x: x, y: y + dy * arm))
        corner.stroke()
    }

    // Handle, lens glass and ring.
    let center = CGPoint(x: 478, y: 548), radius: CGFloat = 212
    let handle = NSBezierPath()
    handle.lineWidth = 66
    handle.lineCapStyle = .round
    handle.move(to: CGPoint(x: center.x + radius * 0.74, y: center.y - radius * 0.74))
    handle.line(to: CGPoint(x: 806, y: 220))
    white.setStroke()
    handle.stroke()

    let lensRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    white.withAlphaComponent(0.16).setFill()
    NSBezierPath(ovalIn: lensRect).fill()
    let ring = NSBezierPath(ovalIn: lensRect)
    ring.lineWidth = 50
    white.setStroke()
    ring.stroke()

    // Lines of text under the lens.
    white.setFill()
    for (offset, width) in [(92.0, 228.0), (0.0, 272.0), (-92.0, 172.0)] as [(CGFloat, CGFloat)] {
        let bar = CGRect(x: center.x - 136, y: center.y + offset - 21, width: width, height: 42)
        NSBezierPath(roundedRect: bar, xRadius: 21, yRadius: 21).fill()
    }

    NSGraphicsContext.current?.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try draw(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.createDirectory(atPath: "build", withIntermediateDirectories: true)
try draw(size: 1024).write(to: URL(fileURLWithPath: "build/icon-preview.png"))
try draw(size: 64).write(to: URL(fileURLWithPath: "build/icon-preview-small.png"))
try? FileManager.default.removeItem(at: iconset)
