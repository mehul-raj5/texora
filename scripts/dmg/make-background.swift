// Draws the DMG window background (660×460 pt) at 1× and 2×.
// Usage: swift scripts/dmg/make-background.swift <out-dir>
import AppKit

let W: CGFloat = 660, H: CGFloat = 460
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    // Work in top-left coordinates like Finder's icon positions.
    let cg = ctx.cgContext
    cg.translateBy(x: 0, y: H)
    cg.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
    NSGraphicsContext.current = flipped

    // Background.
    NSGradient(colors: [color(0x24233A), color(0x1A1A28)])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)
    NSGradient(colors: [color(0xCBA6F7, 0.10), color(0xCBA6F7, 0)])!
        .draw(fromCenter: NSPoint(x: W / 2, y: 170), radius: 0, toCenter: NSPoint(x: W / 2, y: 170), radius: 300, options: [])

    func text(_ s: String, font: NSFont, color c: NSColor, center x: CGFloat, y: CGFloat, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c, .kern: kern]
        let size = (s as NSString).size(withAttributes: attrs)
        (s as NSString).draw(at: NSPoint(x: x - size.width / 2, y: y), withAttributes: attrs)
    }

    text("Drag Texora into Applications", font: .systemFont(ofSize: 15, weight: .semibold), color: color(0xCDD6F4), center: W / 2, y: 34)

    // Arrow between the app (x 165) and Applications (x 495) icons at y 165.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 258, y: 165))
    arrow.line(to: NSPoint(x: 396, y: 165))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.setLineDash([2, 9], count: 2, phase: 0)
    color(0xCBA6F7, 0.85).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 390, y: 156))
    head.line(to: NSPoint(x: 402, y: 165))
    head.line(to: NSPoint(x: 390, y: 174))
    head.lineWidth = 2.5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // "Run this after install" panel, styled like a terminal snippet.
    text("[  RUN THIS AFTER INSTALL  ]", font: .monospacedSystemFont(ofSize: 11, weight: .medium), color: color(0x9399B2), center: W / 2, y: 282, kern: 1.6)
    let box = NSRect(x: 95, y: 304, width: W - 190, height: 46)
    let boxPath = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)
    color(0x11111B, 0.85).setFill(); boxPath.fill()
    color(0x45475A).setStroke(); boxPath.lineWidth = 1; boxPath.stroke()
    // Corner brackets.
    color(0x6C7086).setStroke()
    for (cx, cy, dx, dy) in [(box.minX - 8, box.minY - 8, 1.0, 1.0), (box.maxX + 8, box.minY - 8, -1.0, 1.0),
                             (box.minX - 8, box.maxY + 8, 1.0, -1.0), (box.maxX + 8, box.maxY + 8, -1.0, -1.0)] {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx + 12 * dx, y: cy)); p.line(to: NSPoint(x: cx, y: cy)); p.line(to: NSPoint(x: cx, y: cy + 12 * dy))
        p.lineWidth = 1.2; p.stroke()
    }
    let cmdAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular), .foregroundColor: color(0xCDD6F4)]
    let dollar: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular), .foregroundColor: color(0x7F849C)]
    let line = NSMutableAttributedString(string: "$ ", attributes: dollar)
    line.append(NSAttributedString(string: "xattr -cr /Applications/Texora.app", attributes: cmdAttrs))
    line.draw(at: NSPoint(x: box.minX + 20, y: box.minY + 13))

    text("macOS blocks apps that aren't signed by Apple, and Texora isn't yet.", font: .systemFont(ofSize: 12.5), color: color(0xA6ADC8), center: W / 2, y: 372)
    text("Run this in Terminal once, then open Texora from Applications.", font: .systemFont(ofSize: 12.5), color: color(0xA6ADC8), center: W / 2, y: 391)
    text("Needs Claude Code (claude.com/claude-code) signed in, and a TeX engine: TinyTeX from Settings, or Tectonic.", font: .systemFont(ofSize: 10.5), color: color(0x6C7086), center: W / 2, y: 425)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(scale: 1).write(to: outDir.appendingPathComponent("background.png"))
try! render(scale: 2).write(to: outDir.appendingPathComponent("background@2x.png"))
