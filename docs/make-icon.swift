// Draws the Gridiron Ticker Pro app icon (1024×1024 PNG).
// Usage: swift docs/make-icon.swift <output.png>
import AppKit

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Tile: macOS icon grid (824pt square, 100pt margin), dark like the ticker.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = rgb(0, 0, 0, 0.45)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
rgb(14, 15, 24).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: rgb(36, 38, 58), ending: rgb(10, 10, 16))!.draw(in: tilePath, angle: -90)

// LED ticker dots along the bottom.
let dotY: CGFloat = 196
for i in 0..<11 {
    let x = 232 + CGFloat(i) * 56
    let lit = [1, 2, 3, 5, 6, 8, 9].contains(i)
    (lit ? rgb(255, 200, 70) : rgb(70, 60, 40)).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 13, y: dotY - 13, width: 26, height: 26)).fill()
}

// Football: a pointed ellipse tilted up to the right, drawn in a local frame then rotated.
let c = NSPoint(x: 512, y: 560)
let L: CGFloat = 330   // half length
let Wd: CGFloat = 195  // half width

func footballPath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: -L, y: 0))
    p.curve(to: NSPoint(x: L, y: 0), controlPoint1: NSPoint(x: -L * 0.45, y: Wd * 1.45), controlPoint2: NSPoint(x: L * 0.45, y: Wd * 1.45))
    p.curve(to: NSPoint(x: -L, y: 0), controlPoint1: NSPoint(x: L * 0.45, y: -Wd * 1.45), controlPoint2: NSPoint(x: -L * 0.45, y: -Wd * 1.45))
    p.close()
    return p
}
func place(_ p: NSBezierPath) -> NSBezierPath {
    var t = AffineTransform(translationByX: c.x, byY: c.y)
    t.rotate(byDegrees: 28)
    let q = p.copy() as! NSBezierPath
    q.transform(using: t)
    return q
}

let ball = place(footballPath())

NSGraphicsContext.saveGraphicsState()
let ballShadow = NSShadow()
ballShadow.shadowColor = rgb(0, 0, 0, 0.55)
ballShadow.shadowBlurRadius = 30
ballShadow.shadowOffset = NSSize(width: 0, height: -14)
ballShadow.set()
rgb(120, 60, 28).setFill()
ball.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [rgb(190, 110, 60), rgb(140, 72, 34), rgb(82, 40, 18)],
           atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
    .draw(in: ball, relativeCenterPosition: NSPoint(x: -0.3, y: 0.4))

// White stripes near each end, laces down the middle.
NSGraphicsContext.saveGraphicsState()
ball.addClip()
rgb(245, 245, 245).setFill()
for side: CGFloat in [-1, 1] {
    for off: CGFloat in [0.62, 0.72] {
        place(NSBezierPath(rect: NSRect(x: side * L * off - 9, y: -Wd * 1.6, width: 18, height: Wd * 3.2))).fill()
    }
}
let laces = NSBezierPath()
laces.move(to: NSPoint(x: -L * 0.34, y: 0)); laces.line(to: NSPoint(x: L * 0.34, y: 0))
for i in -3...3 {
    let x = CGFloat(i) * L * 0.1
    laces.move(to: NSPoint(x: x, y: -46)); laces.line(to: NSPoint(x: x, y: 46))
}
laces.lineWidth = 14
laces.lineCapStyle = .round
let placedLaces = place(laces)
placedLaces.lineWidth = 14
placedLaces.lineCapStyle = .round
rgb(245, 245, 245).setStroke()
placedLaces.stroke()
NSGraphicsContext.restoreGraphicsState()

// Subtle rim.
rgb(50, 22, 8, 0.7).setStroke()
ball.lineWidth = 4
ball.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
