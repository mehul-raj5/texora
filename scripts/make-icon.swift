// Renders the Texora app icon (1024×1024 PNG). Usage: swift scripts/make-icon.swift out.png
import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Squircle on Apple's icon grid (824pt content, ~185pt corners) with a soft drop shadow.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset + 6, width: S - 2 * inset, height: S - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: 186, yRadius: 186)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor(srgbRed: 0.12, green: 0.12, blue: 0.18, alpha: 1).setFill()
shape.fill()
ctx.restoreGState()

// Background gradient: deep navy to mocha base.
ctx.saveGState()
shape.addClip()
let bg = NSGradient(colors: [NSColor(srgbRed: 0.20, green: 0.19, blue: 0.30, alpha: 1),
                             NSColor(srgbRed: 0.10, green: 0.10, blue: 0.16, alpha: 1)])!
bg.draw(in: rect, angle: -90)
// Glow behind the letter.
let glow = NSGradient(colors: [NSColor(srgbRed: 0.80, green: 0.65, blue: 0.97, alpha: 0.35), NSColor.clear])!
glow.draw(fromCenter: NSPoint(x: S / 2, y: S / 2 - 20), radius: 0, toCenter: NSPoint(x: S / 2, y: S / 2 - 20), radius: 380, options: [])
ctx.restoreGState()

// The letter T, filled with a lavender→pink gradient.
let font = NSFont(name: "NewYork-Bold", size: 600) ?? NSFont(name: "Times New Roman Bold", size: 600) ?? NSFont.boldSystemFont(ofSize: 600)
let glyphString = NSAttributedString(string: "T", attributes: [.font: font])
let line = CTLineCreateWithAttributedString(glyphString)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
let path = CGMutablePath()
let runs = CTLineGetGlyphRuns(line) as! [CTRun]
for run in runs {
    let count = CTRunGetGlyphCount(run)
    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
    for i in 0..<count {
        var glyph = CGGlyph(); var pos = CGPoint()
        CTRunGetGlyphs(run, CFRange(location: i, length: 1), &glyph)
        CTRunGetPositions(run, CFRange(location: i, length: 1), &pos)
        if let g = CTFontCreatePathForGlyph(runFont, glyph, nil) {
            path.addPath(g, transform: CGAffineTransform(translationX: pos.x, y: pos.y))
        }
    }
}
let tx = (S - bounds.width) / 2 - bounds.minX
let ty = (S - bounds.height) / 2 - bounds.minY - 30
var t = CGAffineTransform(translationX: tx, y: ty)
let placed = path.copy(using: &t)!
ctx.saveGState()
ctx.addPath(placed)
ctx.clip()
let letterGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
    NSColor(srgbRed: 0.96, green: 0.76, blue: 0.91, alpha: 1).cgColor,
    NSColor(srgbRed: 0.80, green: 0.65, blue: 0.97, alpha: 1).cgColor,
    NSColor(srgbRed: 0.54, green: 0.71, blue: 0.98, alpha: 1).cgColor,
] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(letterGradient, start: CGPoint(x: 0, y: ty + bounds.maxY), end: CGPoint(x: 0, y: ty + bounds.minY), options: [])
ctx.restoreGState()

// A four-point sparkle at the top right.
func sparkle(center c: CGPoint, r: CGFloat, color: NSColor) {
    let p = NSBezierPath()
    let k: CGFloat = 0.18
    p.move(to: NSPoint(x: c.x, y: c.y + r))
    p.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + r * k, y: c.y + r * k), controlPoint2: NSPoint(x: c.x + r * k, y: c.y + r * k))
    p.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x + r * k, y: c.y - r * k), controlPoint2: NSPoint(x: c.x + r * k, y: c.y - r * k))
    p.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - r * k, y: c.y - r * k), controlPoint2: NSPoint(x: c.x - r * k, y: c.y - r * k))
    p.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x - r * k, y: c.y + r * k), controlPoint2: NSPoint(x: c.x - r * k, y: c.y + r * k))
    color.setFill()
    p.fill()
}
sparkle(center: CGPoint(x: 735, y: 720), r: 82, color: NSColor(srgbRed: 0.98, green: 0.89, blue: 0.69, alpha: 1))
sparkle(center: CGPoint(x: 815, y: 612), r: 34, color: NSColor(srgbRed: 0.96, green: 0.76, blue: 0.91, alpha: 0.9))

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
