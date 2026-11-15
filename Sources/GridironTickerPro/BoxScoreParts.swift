import AppKit

// Drawing helpers for the box-score popup: scoreboard header, stat bars and leader cards.

/// A team's color that reads on a dark background: the brighter of its two colors, lifted if it's still dim.
func boxAccent(_ hex: (String?, String?)?) -> NSColor {
    let primary = NSColor(hex: hex?.0), alt = NSColor(hex: hex?.1)
    if let p = primary, p.luminance >= 0.12 { return p }
    if let a = alt, a.luminance >= 0.12 { return a }
    guard let c = primary ?? alt else { return NSColor(calibratedWhite: 0.6, alpha: 1) }
    return c.blended(withFraction: 0.5, of: .white) ?? c
}

private func differ(_ a: NSColor, _ b: NSColor) -> Bool {
    guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return true }
    return abs(x.redComponent - y.redComponent) + abs(x.greenComponent - y.greenComponent) + abs(x.blueComponent - y.blueComponent) > 0.35
}

private func attrs(_ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .white, mono: Bool = false) -> [NSAttributedString.Key: Any] {
    [.font: mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight),
     .foregroundColor: color]
}

private extension NSString {
    func drawCentered(in rect: NSRect, _ a: [NSAttributedString.Key: Any]) {
        let s = size(withAttributes: a)
        draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2), withAttributes: a)
    }
}

// MARK: - Header

final class BoxHeaderView: NSView {
    var game: Game?
    var awayColor = NSColor.gray, homeColor = NSColor.gray
    var awayLogo: NSImage?, homeLogo: NSImage?
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 308, height: 108) }

    override func draw(_ dirtyRect: NSRect) {
        guard let g = game else { return }
        let r = bounds
        let shape = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSColor(calibratedWhite: 0.07, alpha: 0.85).setFill()
        r.fill()
        NSGradient(colors: [awayColor.withAlphaComponent(0.42), awayColor.withAlphaComponent(0.05),
                            homeColor.withAlphaComponent(0.05), homeColor.withAlphaComponent(0.42)],
                   atLocations: [0, 0.4, 0.6, 1], colorSpace: .deviceRGB)?.draw(in: r, angle: 0)
        // Team-color strip along the bottom.
        awayColor.setFill(); NSRect(x: 0, y: r.height - 3, width: r.width / 2, height: 3).fill()
        homeColor.setFill(); NSRect(x: r.width / 2, y: r.height - 3, width: r.width / 2, height: 3).fill()
        NSGraphicsContext.restoreGraphicsState()

        let hide = g.scoresHidden
        let showScores = g.state != .upcoming && !hide
        let a = Int(g.away.score ?? ""), h = Int(g.home.score ?? "")
        let awayWon = g.state == .final && (a ?? 0) > (h ?? 0), homeWon = g.state == .final && (h ?? 0) > (a ?? 0)

        for (side, logo, x, won, lost) in [(g.away, awayLogo, CGFloat(10), awayWon, homeWon),
                                           (g.home, homeLogo, r.width - 90, homeWon, awayWon)] {
            let col = NSRect(x: x, y: 8, width: 80, height: 90)
            if let logo { logo.draw(in: NSRect(x: col.midX - 22, y: 10, width: 44, height: 44), from: .zero, operation: .sourceOver, fraction: lost ? 0.55 : 1) }
            (side.name as NSString).drawCentered(in: NSRect(x: col.minX, y: 58, width: col.width, height: 14), attrs(11, .semibold, NSColor(white: 1, alpha: lost ? 0.6 : 1)))
            if let rec = side.record, !rec.isEmpty {
                (rec as NSString).drawCentered(in: NSRect(x: col.minX, y: 73, width: col.width, height: 12), attrs(10, .regular, NSColor(white: 1, alpha: 0.5)))
            }
            _ = won
        }

        let midY: CGFloat = 32
        if showScores {
            let big = { (won: Bool, lost: Bool) in attrs(36, .heavy, NSColor(white: 1, alpha: lost ? 0.5 : 1), mono: true) }
            let aStr = (g.away.score ?? "0") as NSString, hStr = (g.home.score ?? "0") as NSString
            let aa = big(awayWon, homeWon), ha = big(homeWon, awayWon)
            let aw = aStr.size(withAttributes: aa)
            aStr.draw(at: NSPoint(x: r.midX - 16 - aw.width, y: midY - aw.height / 2 + 4), withAttributes: aa)
            hStr.draw(at: NSPoint(x: r.midX + 16, y: midY - aw.height / 2 + 4), withAttributes: ha)
            ("–" as NSString).drawCentered(in: NSRect(x: r.midX - 10, y: midY - 8 + 4, width: 20, height: 20), attrs(18, .light, NSColor(white: 1, alpha: 0.4)))
        } else {
            ("@" as NSString).drawCentered(in: NSRect(x: r.midX - 20, y: midY - 14 + 4, width: 40, height: 32), attrs(28, .light, NSColor(white: 1, alpha: 0.5)))
        }

        // Status pill.
        var label: String
        var fill: NSColor, ink: NSColor = .white
        switch g.state {
        case .live:
            label = "LIVE · " + (hide ? "" : g.detail.uppercased())
            fill = Palette.live
        case .final:
            label = hide ? "FINAL" : g.detail.uppercased()
            fill = NSColor(white: 1, alpha: 0.16)
        case .upcoming:
            label = g.detail.uppercased()
            fill = Palette.upcoming.withAlphaComponent(0.25)
            ink = Palette.upcoming
        }
        if let n = g.network { label += " · " + n.uppercased() }
        label = label.trimmingCharacters(in: CharacterSet(charactersIn: " ·"))
        let pa = attrs(10, .bold, ink)
        let ps = (label as NSString).size(withAttributes: pa)
        let pill = NSRect(x: r.midX - ps.width / 2 - 9, y: 68, width: ps.width + 18, height: 18)
        fill.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
        (label as NSString).drawCentered(in: pill, pa)
    }
}

// MARK: - Stat bars

final class StatBarsView: NSView {
    struct Row { let label: String; let away: String; let home: String }
    var rows: [Row] = [] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var awayColor = NSColor.gray, homeColor = NSColor.gray
    var awayName = "", homeName = ""
    override var isFlipped: Bool { true }
    private let rowH: CGFloat = 34
    override var intrinsicContentSize: NSSize { NSSize(width: 308, height: 20 + CGFloat(rows.count) * rowH) }

    /// A number to compare: "215" -> 215, "29:16" -> 1756 seconds, "3-11" -> 3 (made).
    private func number(_ s: String) -> Double? {
        if s.contains(":") { let p = s.split(separator: ":").compactMap { Double($0) }; return p.count == 2 ? p[0] * 60 + p[1] : nil }
        if s.contains("-"), let m = s.split(separator: "-").first.flatMap({ Double($0) }) { return m }
        return Double(s)
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let ca = differ(awayColor, homeColor) ? awayColor : awayColor, ch = differ(awayColor, homeColor) ? homeColor : NSColor.systemGray
        (awayName as NSString).draw(at: NSPoint(x: 0, y: 0), withAttributes: attrs(11, .bold, ca))
        let hs = (homeName as NSString).size(withAttributes: attrs(11, .bold, ch))
        (homeName as NSString).draw(at: NSPoint(x: w - hs.width, y: 0), withAttributes: attrs(11, .bold, ch))
        var y: CGFloat = 20
        for row in rows {
            let a = number(row.away), h = number(row.home)
            // Who's ahead: fewer turnovers is better; a 3-11 third-down line is judged on the made share.
            var awayLeads = false, homeLeads = false
            if let a, let h, a != h {
                let lowerBetter = row.label == "TO"
                awayLeads = lowerBetter ? a < h : a > h
                homeLeads = !awayLeads
            }
            let lead = attrs(14, .bold, .white, mono: true)
            let trail = attrs(14, .regular, NSColor(white: 1, alpha: 0.5), mono: true)
            let left = row.away as NSString, right = row.home as NSString
            let la = homeLeads ? trail : lead, ra = awayLeads ? trail : lead
            left.draw(at: NSPoint(x: 0, y: y + 8), withAttributes: la)
            let rs = right.size(withAttributes: ra)
            right.draw(at: NSPoint(x: w - rs.width, y: y + 8), withAttributes: ra)
            (row.label as NSString).drawCentered(in: NSRect(x: 0, y: y, width: w, height: 11), attrs(9, .semibold, NSColor(white: 1, alpha: 0.5)))
            // Bar: the whole width split in proportion, away on the left.
            let bx: CGFloat = 62, bw = w - 124, by = y + 14
            let track = NSRect(x: bx, y: by, width: bw, height: 7)
            NSColor(white: 1, alpha: 0.08).setFill()
            NSBezierPath(roundedRect: track, xRadius: 3.5, yRadius: 3.5).fill()
            if let a, let h, a + h > 0, !row.away.contains("-") || row.label != "3RD" {
                let share = CGFloat(a / (a + h))
                let split = bx + bw * share
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: track, xRadius: 3.5, yRadius: 3.5).addClip()
                ca.withAlphaComponent(homeLeads ? 0.5 : 1).setFill(); NSRect(x: bx, y: by, width: split - bx - 1, height: 7).fill()
                ch.withAlphaComponent(awayLeads ? 0.5 : 1).setFill(); NSRect(x: split + 1, y: by, width: bx + bw - split - 1, height: 7).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            y += rowH
        }
    }
}

// MARK: - Leader cards

final class LeaderCardsView: NSView {
    struct Card { let kind: String; let name: String; let detail: String; var photo: NSImage? = nil }
    var groups: [(abbr: String, color: NSColor, cards: [Card])] = [] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var isFlipped: Bool { true }
    private let cardH: CGFloat = 40
    override var intrinsicContentSize: NSSize {
        NSSize(width: 308, height: groups.reduce(0) { $0 + 22 + CGFloat($1.cards.count) * cardH } + 4)
    }

    override func draw(_ dirtyRect: NSRect) {
        var y: CGFloat = 0
        for g in groups {
            (g.abbr as NSString).draw(at: NSPoint(x: 0, y: y + 4), withAttributes: attrs(10, .bold, g.color))
            y += 22
            for c in g.cards {
                let card = NSRect(x: 0, y: y, width: bounds.width, height: cardH - 4)
                NSColor(white: 1, alpha: 0.07).setFill()
                NSBezierPath(roundedRect: card, xRadius: 9, yRadius: 9).fill()
                let circle = NSRect(x: 6, y: y + 2, width: 32, height: 32)
                g.color.withAlphaComponent(0.9).setFill()
                NSBezierPath(ovalIn: circle).fill()
                if let photo = c.photo {
                    // Headshot filling the circle, faces toward the top.
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(ovalIn: circle).addClip()
                    let ar = photo.size.width / max(photo.size.height, 1)
                    let h = circle.height * 1.05, w = h * ar
                    photo.draw(in: NSRect(x: circle.midX - w / 2, y: circle.minY - 1, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1,
                               respectFlipped: true, hints: nil)
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    let initials = c.name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
                    let ink: NSColor = g.color.luminance > 0.5 ? .black : .white
                    (initials as NSString).drawCentered(in: circle, attrs(11, .bold, ink))
                }
                (c.name as NSString).draw(at: NSPoint(x: 46, y: y + 4), withAttributes: attrs(13, .semibold))
                (c.detail as NSString).draw(at: NSPoint(x: 46, y: y + 20), withAttributes: attrs(11, .regular, NSColor(white: 1, alpha: 0.6)))
                let ks = (c.kind as NSString).size(withAttributes: attrs(9, .bold))
                (c.kind as NSString).draw(at: NSPoint(x: card.maxX - ks.width - 10, y: y + 6), withAttributes: attrs(9, .bold, NSColor(white: 1, alpha: 0.4)))
                y += cardH
            }
        }
    }
}
