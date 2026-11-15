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

private func attrs(_ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .white, mono: Bool = false, rounded: Bool = false) -> [NSAttributedString.Key: Any] {
    var font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { font = f }
    return [.font: font, .foregroundColor: color]
}

/// Plays a short ease-out 0...1 value into `update`, unless the user has Reduce Motion on.
@MainActor
final class Ease {
    private var timer: Timer?
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func run(duration: TimeInterval = 0.4, _ update: @escaping (CGFloat) -> Void) {
        timer?.invalidate()
        guard !Ease.reduced else { update(1); return }
        let start = Date()
        update(0)
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] t in
            let x = min(1, CGFloat(Date().timeIntervalSince(start) / duration))
            update(1 - (1 - x) * (1 - x) * (1 - x))
            if x >= 1 { t.invalidate(); self?.timer = nil }
        }
    }
    deinit { timer?.invalidate() }
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
    private var pulse: Timer?
    override var isFlipped: Bool { true }

    /// A live game's red dot breathes; the timer lives only while the header is on screen.
    override func viewDidMoveToWindow() {
        pulse?.invalidate(); pulse = nil
        guard window != nil, game?.state == .live else { return }
        pulse = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in self?.needsDisplay = true }
    }
    deinit { pulse?.invalidate() }
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
            let big = { (won: Bool, lost: Bool) in attrs(38, .black, NSColor(white: 1, alpha: lost ? 0.5 : 1), rounded: true) }
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
        let dotW: CGFloat = g.state == .live ? 12 : 0
        let pill = NSRect(x: r.midX - (ps.width + dotW) / 2 - 9, y: 68, width: ps.width + dotW + 18, height: 18)
        fill.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
        if g.state == .live {
            let a = 0.55 + 0.45 * sin(Date().timeIntervalSinceReferenceDate * 5)
            NSColor.white.withAlphaComponent(CGFloat(a)).setFill()
            NSBezierPath(ovalIn: NSRect(x: pill.minX + 9, y: pill.midY - 3, width: 6, height: 6)).fill()
        }
        (label as NSString).drawCentered(in: NSRect(x: pill.minX + dotW, y: pill.minY, width: pill.width - dotW, height: pill.height), pa)
    }
}

// MARK: - Stat bars

final class StatBarsView: NSView {
    struct Row { let label: String; let away: String; let home: String }
    var rows: [Row] = [] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var awayColor = NSColor.gray, homeColor = NSColor.gray
    var awayName = "", homeName = ""
    private var progress: CGFloat = 1
    private let ease = Ease()
    func animateIn() { ease.run { [weak self] v in self?.progress = v; self?.needsDisplay = true } }
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
                let share = 0.5 + (CGFloat(a / (a + h)) - 0.5) * progress
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

// MARK: - Line score

/// The classic quarter-by-quarter table: 1 2 3 4 (OT) and the total, one row per team.
final class LineScoreView: NSView {
    var away = "", home = ""
    var awayPoints: [String] = [], homePoints: [String] = []
    var awayTotal = "", homeTotal = ""
    var awayColor = NSColor.gray, homeColor = NSColor.gray
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 308, height: 66) }

    override func draw(_ dirtyRect: NSRect) {
        let n = max(4, awayPoints.count, homePoints.count)
        let nameW: CGFloat = 46, totalW: CGFloat = 38
        let colW = (bounds.width - nameW - totalW) / CGFloat(n)
        let dim = NSColor(white: 1, alpha: 0.45)
        func label(_ i: Int) -> String { i < 4 ? "\(i + 1)" : (n - 4 == 1 ? "OT" : "OT\(i - 3)") }
        for i in 0..<n {
            (label(i) as NSString).drawCentered(in: NSRect(x: nameW + CGFloat(i) * colW, y: 0, width: colW, height: 14), attrs(10, .semibold, dim))
        }
        ("T" as NSString).drawCentered(in: NSRect(x: bounds.width - totalW, y: 0, width: totalW, height: 14), attrs(10, .bold, dim))
        for (row, (name, pts, total, color)) in [(away, awayPoints, awayTotal, awayColor), (home, homePoints, homeTotal, homeColor)].enumerated() {
            let y = 18 + CGFloat(row) * 22
            NSColor(white: 1, alpha: row == 0 ? 0.06 : 0.03).setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: bounds.width, height: 20), xRadius: 6, yRadius: 6).fill()
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: y + 3, width: 3, height: 14), xRadius: 1.5, yRadius: 1.5).fill()
            (name as NSString).draw(at: NSPoint(x: 10, y: y + 3), withAttributes: attrs(12, .bold, color))
            for i in 0..<n {
                let v = i < pts.count ? pts[i] : "–"
                let strong = v != "0" && v != "–"
                (v as NSString).drawCentered(in: NSRect(x: nameW + CGFloat(i) * colW, y: y, width: colW, height: 20),
                                             attrs(12, strong ? .semibold : .regular, NSColor(white: 1, alpha: strong ? 0.95 : 0.4), mono: true))
            }
            (total as NSString).drawCentered(in: NSRect(x: bounds.width - totalW, y: y, width: totalW, height: 20), attrs(15, .black, .white, rounded: true))
        }
    }
}

// MARK: - Win probability

/// The home team's chance to win through the game, as a small filled line chart.
final class WinProbView: NSView {
    var probs: [Double] = []      // home team's chance, 0...1
    var away = "", home = ""
    var awayColor = NSColor.gray, homeColor = NSColor.gray
    var live = false
    private var progress: CGFloat = 1
    private let ease = Ease()
    func animateIn() { ease.run(duration: 0.6) { [weak self] v in self?.progress = v; self?.needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 308, height: 92) }

    override func draw(_ dirtyRect: NSRect) {
        let title = attrs(9, .semibold, NSColor(white: 1, alpha: 0.5))
        ("WIN PROBABILITY" as NSString).draw(at: NSPoint(x: 0, y: 0), withAttributes: title)
        guard probs.count > 1 else { return }
        let chart = NSRect(x: 0, y: 16, width: bounds.width, height: 60)
        let mid = chart.midY
        NSColor(white: 1, alpha: 0.05).setFill()
        NSBezierPath(roundedRect: chart, xRadius: 6, yRadius: 6).fill()
        func pt(_ i: Int) -> NSPoint {
            NSPoint(x: chart.minX + chart.width * CGFloat(i) / CGFloat(probs.count - 1),
                    y: chart.minY + chart.height * (1 - CGFloat(min(max(probs[i], 0), 1))))
        }
        let shown = max(2, Int(CGFloat(probs.count) * progress))
        let line = NSBezierPath()
        line.move(to: pt(0))
        for i in 1..<shown { line.line(to: pt(i)) }
        let lastShown = pt(shown - 1)
        // Fill between the line and the 50% mark: home color where the home team leads, away color where it trails.
        let area = line.copy() as! NSBezierPath
        area.line(to: NSPoint(x: lastShown.x, y: mid)); area.line(to: NSPoint(x: chart.minX, y: mid)); area.close()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: chart, xRadius: 6, yRadius: 6).addClip()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: chart.minX, y: chart.minY, width: chart.width, height: chart.height / 2)).addClip()
        homeColor.withAlphaComponent(0.55).setFill(); area.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: chart.minX, y: mid, width: chart.width, height: chart.height / 2)).addClip()
        awayColor.withAlphaComponent(0.55).setFill(); area.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 1, alpha: 0.25).setStroke()
        let m = NSBezierPath(); m.move(to: NSPoint(x: chart.minX, y: mid)); m.line(to: NSPoint(x: chart.maxX, y: mid))
        m.lineWidth = 0.5; m.setLineDash([3, 3], count: 2, phase: 0); m.stroke()
        NSColor.white.setStroke()
        line.lineWidth = 1.6; line.lineJoinStyle = .round; line.stroke()
        NSGraphicsContext.restoreGraphicsState()
        // The latest point.
        let last = lastShown
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)).fill()
        // Team labels and the current odds.
        (home as NSString).draw(at: NSPoint(x: 6, y: chart.minY + 3), withAttributes: attrs(9, .bold, homeColor))
        (away as NSString).draw(at: NSPoint(x: 6, y: chart.maxY - 14), withAttributes: attrs(9, .bold, awayColor))
        let hp = probs[probs.count - 1]
        let text = hp >= 0.5 ? "\(home) \(Int((hp * 100).rounded()))%" : "\(away) \(Int(((1 - hp) * 100).rounded()))%"
        let ts = (text as NSString).size(withAttributes: title)
        (text as NSString).draw(at: NSPoint(x: bounds.width - ts.width, y: 0), withAttributes: attrs(9, .bold, NSColor(white: 1, alpha: 0.8)))
    }
}

// MARK: - Scoring summary

final class ScoringSummaryView: NSView {
    struct Item { let period: Int; let clock: String; let abbr: String; let color: NSColor; let text: String; let kind: String; let away: Int; let home: Int }
    var items: [Item] = [] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var isFlipped: Bool { true }
    private let rowH: CGFloat = 24
    override var intrinsicContentSize: NSSize { NSSize(width: 308, height: 16 + CGFloat(items.count) * rowH) }

    private func quarter(_ p: Int) -> String { p >= 1 && p <= 4 ? "Q\(p)" : "OT" }

    override func draw(_ dirtyRect: NSRect) {
        ("SCORING" as NSString).draw(at: NSPoint(x: 0, y: 0), withAttributes: attrs(9, .semibold, NSColor(white: 1, alpha: 0.5)))
        var y: CGFloat = 16
        for it in items {
            let icon = NSRect(x: 0, y: y + 3, width: 18, height: 18)
            it.color.withAlphaComponent(0.25).setFill()
            NSBezierPath(ovalIn: icon).fill()
            drawIcon(it.kind, in: icon, color: it.color)
            let head = "\(quarter(it.period)) \(it.clock) · \(it.abbr)"
            (head as NSString).draw(at: NSPoint(x: 24, y: y + 1), withAttributes: attrs(9, .semibold, NSColor(white: 1, alpha: 0.5)))
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
            var a = attrs(11, .regular, .white); a[.paragraphStyle] = para
            (it.text as NSString).draw(in: NSRect(x: 24, y: y + 11, width: bounds.width - 24 - 44, height: 13), withAttributes: a)
            let score = "\(it.away)–\(it.home)"
            let ss = (score as NSString).size(withAttributes: attrs(11, .semibold, mono: true))
            (score as NSString).draw(at: NSPoint(x: bounds.width - ss.width, y: y + 6), withAttributes: attrs(11, .semibold, NSColor(white: 1, alpha: 0.8), mono: true))
            y += rowH
        }
    }

    /// A tiny football for touchdowns, goalposts for field goals, an S for a safety.
    private func drawIcon(_ kind: String, in r: NSRect, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        switch kind {
        case "FG":
            let p = NSBezierPath()
            let cx = r.midX
            p.move(to: NSPoint(x: cx, y: r.maxY - 3)); p.line(to: NSPoint(x: cx, y: r.midY + 1))
            p.move(to: NSPoint(x: cx - 4, y: r.midY + 1)); p.line(to: NSPoint(x: cx + 4, y: r.midY + 1))
            p.move(to: NSPoint(x: cx - 4, y: r.midY + 1)); p.line(to: NSPoint(x: cx - 4, y: r.minY + 3))
            p.move(to: NSPoint(x: cx + 4, y: r.midY + 1)); p.line(to: NSPoint(x: cx + 4, y: r.minY + 3))
            p.lineWidth = 1.4; NSColor.white.setStroke(); p.stroke()
        case "SAF":
            ("S" as NSString).drawCentered(in: r, attrs(10, .heavy, .white))
        default:
            let ball = NSBezierPath(ovalIn: NSRect(x: r.midX - 5.5, y: r.midY - 3.2, width: 11, height: 6.4))
            NSColor(calibratedRed: 0.72, green: 0.38, blue: 0.16, alpha: 1).setFill(); ball.fill()
            NSColor.white.setStroke(); ball.lineWidth = 0.7; ball.stroke()
            let l = NSBezierPath(); l.move(to: NSPoint(x: r.midX - 2, y: r.midY)); l.line(to: NSPoint(x: r.midX + 2, y: r.midY))
            l.lineWidth = 0.8; l.stroke()
        }
    }
}

// MARK: - Fantasy strip

struct FantasyEntry { let name: String; let pos: String; let points: Double; let detail: String }

/// Your fantasy players in this game: a gold card, names on the left, big points on the right.
final class FantasyStripView: NSView {
    var entries: [FantasyEntry] = [] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var isFlipped: Bool { true }
    private let rowH: CGFloat = 38
    override var intrinsicContentSize: NSSize { NSSize(width: 308, height: 34 + CGFloat(entries.count) * rowH) }

    override func draw(_ dirtyRect: NSRect) {
        let gold = Palette.favorite
        let box = bounds.insetBy(dx: 0.5, dy: 0.5)
        gold.withAlphaComponent(0.11).setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        gold.withAlphaComponent(0.4).setStroke()
        let edge = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12); edge.lineWidth = 1; edge.stroke()
        ("★ YOUR FANTASY PLAYERS" as NSString).draw(at: NSPoint(x: 12, y: 10), withAttributes: [.font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: gold, .kern: 0.8])
        let total = entries.reduce(0) { $0 + $1.points }
        if entries.count > 1 {
            let t = "TOTAL \(fantasyFormat(total))" as NSString
            let ts = t.size(withAttributes: attrs(10, .bold))
            t.draw(at: NSPoint(x: bounds.width - 12 - ts.width, y: 9), withAttributes: attrs(10, .bold, gold))
        }
        var y: CGFloat = 28
        for e in entries {
            (e.name as NSString).draw(at: NSPoint(x: 12, y: y + 2), withAttributes: attrs(13, .semibold))
            ("\(e.pos)" as NSString).draw(at: NSPoint(x: 12 + (e.name as NSString).size(withAttributes: attrs(13, .semibold)).width + 6, y: y + 5), withAttributes: attrs(9, .bold, NSColor(white: 1, alpha: 0.45)))
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
            var da = attrs(10, .regular, NSColor(white: 1, alpha: 0.55)); da[.paragraphStyle] = para
            (e.detail as NSString).draw(in: NSRect(x: 12, y: y + 19, width: bounds.width - 24 - 62, height: 13), withAttributes: da)
            let pts = fantasyFormat(e.points) as NSString
            let ps = pts.size(withAttributes: attrs(24, .black, gold, rounded: true))
            pts.draw(at: NSPoint(x: bounds.width - 12 - ps.width, y: y + 2), withAttributes: attrs(24, .black, gold, rounded: true))
            y += rowH
        }
    }
}
