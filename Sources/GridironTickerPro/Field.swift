import AppKit

/// A small football field for a live game: both end zones, 10-yard lines, the ball, and the line to gain.
/// ESPN's yardLine runs from the home goal line (0) to the away goal line (100). The away team is drawn on the
/// left, so the away team drives right and the home team drives left.
final class FieldView: NSView {
    var away = "", home = ""
    var situation: Situation?
    var awayHasBall = false

    override var intrinsicContentSize: NSSize { NSSize(width: 300, height: 46) }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let ez: CGFloat = 26
        let field = NSRect(x: r.minX + ez, y: r.minY + 8, width: r.width - 2 * ez, height: r.height - 16)
        NSColor(calibratedRed: 0.13, green: 0.40, blue: 0.20, alpha: 1).setFill()
        NSRect(x: r.minX, y: field.minY, width: r.width, height: field.height).fill()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSRect(x: r.minX, y: field.minY, width: ez, height: field.height).fill()
        NSRect(x: r.maxX - ez, y: field.minY, width: ez, height: field.height).fill()
        // End-zone labels, rotated like on TV.
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.8)]
        for (label, left) in [(away, true), (home, false)] {
            let s = NSAttributedString(string: label, attributes: attrs)
            let size = s.size()
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.translateX(by: left ? r.minX + ez / 2 : r.maxX - ez / 2, yBy: r.midY)
            t.rotate(byDegrees: left ? 90 : -90)
            t.concat()
            s.draw(at: NSPoint(x: -size.width / 2, y: -size.height / 2))
            NSGraphicsContext.restoreGraphicsState()
        }
        // Yard lines every 10.
        NSColor(calibratedWhite: 1, alpha: 0.35).setStroke()
        for i in 0...10 {
            let x = field.minX + field.width * CGFloat(i) / 10
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x, y: field.minY)); p.line(to: NSPoint(x: x, y: field.maxY))
            p.lineWidth = i == 0 || i == 10 ? 1.5 : 0.7
            p.stroke()
        }
        guard let s = situation, let yl = s.yardLine else { return }
        func x(_ yardLine: Int) -> CGFloat { field.minX + field.width * (1 - CGFloat(min(max(yardLine, 0), 100)) / 100) }
        // Line to gain: the away team moves toward 0, the home team toward 100.
        if s.down > 0, s.distance > 0 {
            let target = awayHasBall ? yl - s.distance : yl + s.distance
            if (0...100).contains(target) {
                NSColor(calibratedRed: 1, green: 0.85, blue: 0.1, alpha: 1).setStroke()
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x(target), y: field.minY)); p.line(to: NSPoint(x: x(target), y: field.maxY))
                p.lineWidth = 2
                p.stroke()
            }
        }
        // The ball.
        let bx = x(yl), by = field.midY
        let ball = NSBezierPath(ovalIn: NSRect(x: bx - 6, y: by - 3.5, width: 12, height: 7))
        NSColor(calibratedRed: 0.62, green: 0.32, blue: 0.14, alpha: 1).setFill()
        ball.fill()
        NSColor.white.setStroke()
        ball.lineWidth = 0.8
        ball.stroke()
    }
}
