import AppKit

// MARK: - Ticker rendering

enum Palette {
    static let rank = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.2, alpha: 1)
    static let name = NSColor.white
    static let favorite = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.35, alpha: 1)
    static let liveScore = NSColor(calibratedRed: 0.35, green: 1.0, blue: 0.45, alpha: 1)
    static let score = NSColor(calibratedWhite: 0.92, alpha: 1)
    static let live = NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.3, alpha: 1)
    static let upcoming = NSColor(calibratedRed: 0.4, green: 0.85, blue: 1.0, alpha: 1)
    static let final = NSColor(calibratedWhite: 1, alpha: 0.62)   // see-through, so it suits team-colored bars too
    static let dim = NSColor(calibratedWhite: 1, alpha: 0.45)
    static let network = NSColor(calibratedWhite: 0.72, alpha: 1)
    static let alert = NSColor(calibratedRed: 1.0, green: 0.22, blue: 0.2, alpha: 1)
    static let marquee = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.2, alpha: 1)
}

extension NSColor {
    convenience init?(hex: String?) {
        guard let hex, hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
    /// WCAG relative luminance, 0 (black) to 1 (white).
    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 0 }
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }
}

/// A team's bar colors: the primary color, darkened if needed so white and gold text stay
/// readable, and an accent stripe from the second color (or the primary when that's too dark).
func teamBarColors(primary: String?, alternate: String?) -> (background: NSColor, accent: NSColor)? {
    guard let base = NSColor(hex: primary) else { return nil }
    var bg = base
    var step: CGFloat = 0
    while bg.luminance > 0.12 && step < 0.9 {
        step += 0.05
        bg = base.blended(withFraction: step, of: .black) ?? base
    }
    var accent = NSColor(hex: alternate) ?? .white
    if accent.luminance < 0.1 || abs(accent.luminance - bg.luminance) < 0.05 { accent = base.luminance > 0.1 ? base : .white }
    return (bg, accent)
}

/// Whether a live game's change between two refreshes deserves a glow.
/// mode: 0 off, 1 the favorite team scored, 2 big moments, 3 any score change.
func shouldFlash(prev: Game, now: Game, mode: Int, followed: Set<String>) -> Bool {
    func pts(_ s: Side) -> Int? { Int(s.score ?? "") }
    guard let pa = pts(prev.away), let ph = pts(prev.home), let na = pts(now.away), let nh = pts(now.home),
          (pa, ph) != (na, nh) else { return false }
    switch mode {
    case 1:
        return (followed.contains(now.away.teamID) && na > pa) || (followed.contains(now.home.teamID) && nh > ph)
    case 2:
        let before = pa - ph, after = na - nh
        let leadChange = before != 0 && after != 0 && (before > 0) != (after > 0)
        let tie = after == 0 && before != 0
        func late(_ g: Game) -> Bool { g.period >= 2 && g.clock <= 240 && !g.isHalftime }
        let onePossession = late(now) && abs(after) <= 3 && (abs(before) > 3 || !late(prev))
        return leadChange || tie || onePossession
    case 3:
        return true
    default:
        return false
    }
}

/// One attributed string per game (separator included), so the ticker only draws what's on screen.
@MainActor
func buildTickerSegments(_ games: [Game], followed: Set<String>, font: NSFont, separator: Bool = true) -> [NSAttributedString] {
    var out = NSMutableAttributedString()
    var parts: [NSAttributedString] = []
    func add(_ s: String, _ c: NSColor) {
        out.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c]))
    }
    func team(_ s: Side, showScore: Bool, live: Bool) {
        if Prefs.showLogos, let logo = LogoStore.shared.attachment(for: s.teamID, abbr: s.abbr, font: font) {
            out.append(NSAttributedString(attachment: logo))
            add(" ", Palette.dim)
        }
        add(s.name.uppercased(), followed.contains(s.teamID) ? Palette.favorite : Palette.name)
        if Prefs.showRecords, let rec = s.record, !rec.isEmpty { add(" (\(rec))", Palette.dim) }
        if showScore, let sc = s.score { add(" \(sc)", live ? Palette.liveScore : Palette.score) }
    }

    /// "HOU -10 · O/U 44.5", or nil when ESPN has no line for the game.
    func oddsText(_ g: Game) -> String? {
        var bits: [String] = []
        if let d = g.odds, !d.isEmpty { bits.append(d) }
        if let ou = g.overUnder { bits.append("O/U " + (ou == ou.rounded() ? String(Int(ou)) : String(ou))) }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    if games.isEmpty {
        add("NO GAMES TO SHOW RIGHT NOW", Palette.dim)
        add("          ", Palette.dim)
        return [out]
    }
    for g in games {
        let mine = followed.contains(g.away.teamID) || followed.contains(g.home.teamID)
        if mine { add("★ ", Palette.favorite) }
        let hide = g.scoresHidden
        if Prefs.showMarquee, g.isMarquee {
            // Black on gold: a different badge from the red alerts, and it can sit next to one.
            out.append(NSAttributedString(string: " MARQUEE ", attributes: [.font: font, .foregroundColor: NSColor.black,
                                                                          .backgroundColor: Palette.marquee]))
            add("  ", Palette.dim)
        }
        if Prefs.showAlertTags, !hide, let tag = g.isUpsetBrewing ? "UPSET ALERT" : (g.isCloseLate ? "CLOSE" : nil) {
            // White on red, so it reads as a badge rather than more ticker text.
            out.append(NSAttributedString(string: " \(tag) ", attributes: [.font: font, .foregroundColor: NSColor.white,
                                                                          .backgroundColor: Palette.alert]))
            add("  ", Palette.dim)
        }
        switch g.state {
        case .live:
            team(g.away, showScore: !hide, live: true)
            add(hide ? "  @  " : "  –  ", Palette.dim)
            team(g.home, showScore: !hide, live: true)
            add("   \(hide ? "LIVE" : g.detail.uppercased())", Palette.live)
            if let r = g.round { add(" · \(r)", Palette.rank) }
            // Where to watch your own team's game while it's on.
            if mine, let n = g.network { add(" · \(n.uppercased())", Palette.network) }
        case .final:
            team(g.away, showScore: !hide, live: false)
            add(hide ? "  @  " : "  –  ", Palette.dim)
            team(g.home, showScore: !hide, live: false)
            add("   \(hide ? "FINAL" : g.detail.uppercased())", Palette.final)
            if let r = g.round { add(" · \(r)", Palette.rank) }
        case .upcoming:
            team(g.away, showScore: false, live: false)
            add("  @  ", Palette.dim)
            team(g.home, showScore: false, live: false)
            add("   \(g.detail.uppercased())", Palette.upcoming)
            if let r = g.round { add(" · \(r)", Palette.rank) }
            if let n = g.network { add(" · \(n.uppercased())", Palette.network) }
        }
        if Prefs.showOdds, g.state != .final, let line = oddsText(g) { add(" · \(line)", Palette.network) }
        if separator { add("      ◆      ", Palette.dim) }
        parts.append(out)
        out = NSMutableAttributedString()
    }
    return parts
}

/// Scrolls the games with Core Animation: each game is drawn once into a small image,
/// and the GPU slides a strip of those images. Only games within about a screen's width
/// of the visible area exist as layers at any moment, so CPU and memory stay flat.
final class TickerView: NSView {
    private struct Segment { let text: NSAttributedString; let x: CGFloat; let width: CGFloat }

    private var lastParts: [NSAttributedString] = []
    private var segments: [Segment] = []
    private var total: CGFloat = 0
    private let strip = CALayer()
    private let accent = CALayer()
    private var liveLayers: [String: CALayer] = [:]   // "segment:copy" -> layer
    private var images: [Int: CGImage] = [:]          // segment -> rendered image
    private var tick: Timer?
    private var centered = false   // one still segment in the middle instead of scrolling
    private var background = NSColor.black
    private var accentHeight: CGFloat = 1
    /// 1 is solid black (or the team color); less lets the desktop show through.
    var barOpacity: CGFloat = 1 {
        didSet {
            guard barOpacity != oldValue else { return }
            layer!.backgroundColor = background.withAlphaComponent(barOpacity).cgColor
            clearLayers()
            updateVisible()
        }
    }
    private var downAt: NSPoint?
    private var keys: [String] = []               // game id for each segment ("" for messages)
    private var pendingFlash = Set<String>()      // games whose score changed, waiting to be on screen
    private var hand = false
    private var paused = false

    /// Called with the index of the segment that was clicked.
    var onClick: ((Int, CGFloat) -> Void)?

    /// Points per frame at 60 fps (kept from the original timer-based ticker).
    var speed: CGFloat = 2.0 {
        didSet { if speed != oldValue { restart(at: currentOffset()) } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer!.backgroundColor = NSColor.black.cgColor
        layer!.masksToBounds = true
        strip.anchorPoint = .zero
        strip.actions = ["position": NSNull(), "sublayers": NSNull(), "bounds": NSNull()]
        layer!.addSublayer(strip)
        accent.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 1).cgColor
        accent.actions = ["position": NSNull(), "bounds": NSNull()]
        layer!.addSublayer(accent)
        // Light bookkeeping a few times a second: add layers coming into view, drop ones that left.
        tick = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.updateVisible() }
        RunLoop.main.add(tick!, forMode: .common)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ parts: [NSAttributedString], keys: [String] = []) {
        self.keys = keys
        // Refreshes usually change nothing; skip the rebuild so scrolling isn't disturbed.
        guard parts != lastParts || centered else { return }
        let wasCentered = centered
        centered = false
        lastParts = parts
        let keep = currentOffset()
        var x: CGFloat = 0
        segments = parts.map { s in
            let w = ceil(s.size().width)
            defer { x += w }
            return Segment(text: s, x: x, width: w)
        }
        total = x
        clearLayers()
        restart(at: total > 0 && !wasCentered ? keep.truncatingRemainder(dividingBy: total) : 0)
    }

    /// Shows one segment, still and centered. Unchanged text costs nothing.
    func setCentered(_ text: NSAttributedString, key: String = "") {
        keys = [key]
        guard !centered || segments.first?.text != text else { return }
        centered = true
        lastParts = []
        let w = ceil(text.size().width)
        segments = [Segment(text: text, x: 0, width: w)]
        total = w
        clearLayers()
        restart(at: 0)
    }

    /// Bar colors: black with a thin grey line normally, or a team's colors.
    func setColors(background bg: NSColor, accent: NSColor, accentHeight h: CGFloat) {
        guard bg != background || accent.cgColor != self.accent.backgroundColor || h != accentHeight else { return }
        background = bg
        accentHeight = h
        layer!.backgroundColor = bg.withAlphaComponent(barOpacity).cgColor
        self.accent.backgroundColor = accent.cgColor
        needsLayout = true
        clearLayers()   // segment images have the old background baked in
        updateVisible()
    }

    /// Glow these games once each, as soon as they're on screen (now, if they already are).
    func flash(_ ids: Set<String>) {
        pendingFlash.formUnion(ids.subtracting([""]))
        updateVisible()
    }

    /// Jump back so the first game is at the left edge.
    func resetToStart() { restart(at: 0) }

    override func layout() {
        super.layout()
        accent.frame = CGRect(x: 0, y: Prefs.atTop ? 0 : bounds.height - accentHeight, width: bounds.width, height: accentHeight)
        if centered { restart(at: 0) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let heightChanged = newSize.height != frame.height
        super.setFrameSize(newSize)
        if heightChanged { clearLayers() }
        needsLayout = true
        updateVisible()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        clearLayers()
        updateVisible()
    }

    // MARK: Clicks

    // The panel never becomes active, so take the very first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { downAt = convert(event.locationInWindow, from: nil) }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        defer { downAt = nil }
        guard let d = downAt, hypot(p.x - d.x, p.y - d.y) < 6, let i = segmentIndex(at: p.x) else { return }
        onClick?(i, p.x)
    }

    /// Which segment is under this x position right now (the strip may be mid-scroll).
    private func segmentIndex(at x: CGFloat) -> Int? {
        guard total > 0 else { return nil }
        let sx = x - (strip.presentation() ?? strip).position.x
        if centered { return sx >= 0 && sx < total ? 0 : nil }
        var o = sx.truncatingRemainder(dividingBy: total)
        if o < 0 { o += total }
        return segments.firstIndex { o >= $0.x && o < $0.x + $0.width }
    }

    // Pointing-hand cursor over the ticker, even though the app is never frontmost.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    private var hovering = false
    private var held = false

    override func mouseEntered(with event: NSEvent) {
        if !hand { NSCursor.pointingHand.push(); hand = true }
        hovering = true
        applyPause()
    }
    override func mouseExited(with event: NSEvent) {
        if hand { NSCursor.pop(); hand = false }
        hovering = false
        applyPause()
    }

    /// Hold the strip still (for example while a popup is open on it).
    func hold(_ on: Bool) {
        held = on
        applyPause()
    }

    private func applyPause() { setPaused(held || (hovering && Prefs.pauseOnHover)) }

    /// Hold the strip where it is (so a score can be read), or carry on from there.
    private func setPaused(_ p: Bool) {
        guard p != paused else { return }
        let here = currentOffset()
        paused = p
        restart(at: here)
    }

    // MARK: Scrolling

    private func currentOffset() -> CGFloat {
        guard total > 0, !centered else { return 0 }
        let x = (strip.presentation() ?? strip).position.x
        let o = (-x).truncatingRemainder(dividingBy: total)
        return o < 0 ? o + total : o
    }

    private func restart(at offset: CGFloat) {
        strip.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.position = CGPoint(x: centered ? ((bounds.width - total) / 2).rounded() : -offset, y: 0)
        CATransaction.commit()
        if centered || paused { updateVisible(offset: offset); return }
        let pointsPerSecond = speed * 60
        if total > 0, pointsPerSecond > 0 {
            let anim = CABasicAnimation(keyPath: "position.x")
            anim.fromValue = 0
            anim.toValue = -total
            anim.duration = Double(total / pointsPerSecond)
            anim.repeatCount = .infinity
            anim.timeOffset = Double(offset / pointsPerSecond)
            anim.isRemovedOnCompletion = false
            strip.add(anim, forKey: "scroll")
        }
        updateVisible(offset: offset)
    }

    // MARK: Layers

    private func clearLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        liveLayers.values.forEach { $0.removeFromSuperlayer() }
        CATransaction.commit()
        liveLayers.removeAll()
        images.removeAll()
    }

    private func updateVisible(offset: CGFloat? = nil) {
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return }
        let off = offset ?? currentOffset()
        let margin = bounds.width
        // Cover the visible window plus a margin, and the same window one loop earlier,
        // so the layers are already there when the animation wraps back to the start.
        let ranges = centered ? [(CGFloat(0), total / 2)]
            : [(off - margin, off + bounds.width + margin),
               (off - total - margin, off - total + bounds.width + margin)]
        let scale = window?.backingScaleFactor ?? 2
        let h = bounds.height

        var wanted = Set<String>()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (start, end) in ranges {
            for j in Int((start / total).rounded(.down))...Int((end / total).rounded(.down)) {
                for (i, s) in segments.enumerated() {
                    let x = CGFloat(j) * total + s.x
                    guard x + s.width > start, x < end else { continue }
                    let key = "\(i):\(j)"
                    guard wanted.insert(key).inserted, liveLayers[key] == nil else { continue }
                    let l = CALayer()
                    l.isOpaque = barOpacity >= 1
                    l.contentsScale = scale
                    l.contents = image(for: i, scale: scale, height: h)
                    l.frame = CGRect(x: x, y: 0, width: s.width, height: h)
                    strip.addSublayer(l)
                    liveLayers[key] = l
                }
            }
        }
        for (key, l) in liveLayers where !wanted.contains(key) {
            l.removeFromSuperlayer()
            liveLayers[key] = nil
        }
        if !pendingFlash.isEmpty { flashVisible(offset: off) }
        CATransaction.commit()
        let inUse = Set(liveLayers.keys.compactMap { Int($0.split(separator: ":")[0]) })
        images = images.filter { inUse.contains($0.key) }
    }

    /// Pulse a highlight over any pending game that has scrolled well into view.
    private func flashVisible(offset off: CGFloat) {
        let viewLeft = centered ? -CGFloat.infinity : off
        let viewRight = centered ? CGFloat.infinity : off + bounds.width
        var done = Set<String>()
        for (key, l) in liveLayers {
            guard let i = Int(key.split(separator: ":")[0]), keys.indices.contains(i),
                  pendingFlash.contains(keys[i]) else { continue }
            // The layer's x is in strip coordinates, the same space as the offset.
            // Wait until most of the game is on screen, so the glow is seen.
            let x = l.frame.minX, need = min(l.frame.width, bounds.width) * 0.75
            guard x + l.frame.width >= viewLeft + need, x <= viewRight - need else { continue }
            let glow = CALayer()
            glow.frame = l.bounds.insetBy(dx: 2, dy: 4)
            glow.cornerRadius = 6
            glow.backgroundColor = Palette.liveScore.withAlphaComponent(0.22).cgColor
            glow.borderColor = Palette.liveScore.withAlphaComponent(0.55).cgColor
            glow.borderWidth = 1.5
            glow.opacity = 0
            l.addSublayer(glow)
            // One soft fade in and out.
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.3, 0.5, 1]
            fade.duration = 2.2
            fade.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .linear),
                                    CAMediaTimingFunction(name: .easeInEaseOut)]
            glow.add(fade, forKey: "flash")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { glow.removeFromSuperlayer() }
            done.insert(keys[i])
        }
        pendingFlash.subtract(done)
    }

    private func image(for i: Int, scale: CGFloat, height: CGFloat) -> CGImage? {
        if let cached = images[i] { return cached }
        let s = segments[i]
        let w = Int((s.width * scale).rounded(.up)), h = Int((height * scale).rounded(.up))
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: (barOpacity < 1 ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        if barOpacity >= 1 {   // see-through bars leave the background to the layer behind
            ctx.setFillColor(background.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s.width, height: height))
        }
        // AppKit string drawing honors the NSColor attributes (Core Text's CTLineDraw ignores them).
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        s.text.draw(at: NSPoint(x: 0, y: ((height - s.text.size().height) / 2).rounded()))
        NSGraphicsContext.restoreGraphicsState()
        let img = ctx.makeImage()
        images[i] = img
        return img
    }
}

// MARK: - Menu bar icon

/// The app icon football, drawn as a vector so it stays sharp at menu bar size.
func menuBarBall() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
        let L: CGFloat = 8, W: CGFloat = 4.6
        let p = NSBezierPath()
        p.move(to: NSPoint(x: -L, y: 0))
        p.curve(to: NSPoint(x: L, y: 0), controlPoint1: NSPoint(x: -L * 0.45, y: W * 1.45), controlPoint2: NSPoint(x: L * 0.45, y: W * 1.45))
        p.curve(to: NSPoint(x: -L, y: 0), controlPoint1: NSPoint(x: L * 0.45, y: -W * 1.45), controlPoint2: NSPoint(x: -L * 0.45, y: -W * 1.45))
        p.close()
        var t = AffineTransform(translationByX: rect.midX, byY: rect.midY)
        t.rotate(byDegrees: 28)
        p.transform(using: t)
        NSGradient(colors: [NSColor(calibratedRed: 0.75, green: 0.43, blue: 0.24, alpha: 1),
                            NSColor(calibratedRed: 0.55, green: 0.28, blue: 0.13, alpha: 1),
                            NSColor(calibratedRed: 0.32, green: 0.16, blue: 0.07, alpha: 1)],
                   atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
            .draw(in: p, relativeCenterPosition: NSPoint(x: -0.3, y: 0.4))

        let laces = NSBezierPath()
        laces.move(to: NSPoint(x: -2.6, y: 0)); laces.line(to: NSPoint(x: 2.6, y: 0))
        for i in -2...2 {
            let x = CGFloat(i) * 1.2
            laces.move(to: NSPoint(x: x, y: -1.2)); laces.line(to: NSPoint(x: x, y: 1.2))
        }
        laces.transform(using: t)
        laces.lineWidth = 0.9
        NSColor(white: 0.96, alpha: 1).setStroke()
        laces.stroke()
        return true
    }
    img.accessibilityDescription = "Gridiron Ticker Pro"
    return img
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: NSPanel!
    private var ticker: TickerView!
    private var statusItem: NSStatusItem!
    private let settings = SettingsController()
    private let alerts = TeamAlerts()
    private let boxPopover = BoxScorePopover()
    private let fantasyWindow = FantasyWindowController()

    private var games: [Game] = []          // today
    private var lookahead: [[Game]] = []    // tomorrow onward, one array per day
    private var scheduleNext: [String: Game] = [:]   // each followed team's next game, from its season schedule
    private var lastUpdate: Date?
    private var lastError: String?
    private var slowDownUntil = Date.distantPast   // when ESPN asked us to back off, until when
    private var refreshTask: Task<Void, Never>?
    private var forceShown = false          // auto-hide is on, but you chose Show Ticker
    private var forceHidden = false         // auto-hide is on, but you chose Hide Ticker during a game
    private var knownChannels = Set<String>()
    private var shownGames: [Game] = []     // what each ticker segment is, for clicks
    private var teamNameByID: [String: String] = [:]
    private var teamColors: [String: (String?, String?)] = [:]   // team id -> (primary, alternate) hex
    private var lastLive: [String: Game] = [:]   // previous snapshot of each live game, to spot baskets
    private var lastFullRefresh = Date.distantPast

    private let lookaheadDays = 1
    private var barHeight: CGFloat { Prefs.fontPoints + 22 }   // 44 at the default 22 pt text
    private var font: NSFont { .monospacedSystemFont(ofSize: Prefs.fontPoints, weight: .heavy) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ticker = TickerView(frame: .zero)
        ticker.speed = CGFloat(Prefs.speed)
        panel.contentView = ticker

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = menuBarBall()
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        ticker.menu = menu
        ticker.onClick = { [weak self] i, x in self?.gameClicked(at: i, x: x) }
        boxPopover.onOpenESPN = { [weak self] g in self?.openESPN(g) }
        boxPopover.extraLines = { g in FantasyStore.shared.lines(in: g) }
        FantasyStore.shared.onChange = { [weak self] in self?.render(); self?.fantasyWindow.refresh() }
        fantasyWindow.onChange = { [weak self] in
            self?.render()
            Task { @MainActor in
                await FantasyStore.shared.refresh(games: self?.games ?? [], next: self?.lookahead.first ?? [], week: await ESPN.currentWeek())
                self?.render()
            }
        }
        boxPopover.onVisibility = { [weak self] open in self?.ticker.hold(open) }
        LogoStore.shared.onLoad = { [weak self] in self?.render() }

        settings.onChange = { [weak self] change in self?.settingChanged(change) }

        NotificationCenter.default.addObserver(self, selector: #selector(layoutPanel),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        layoutPanel()
        applyLook()
        render()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateVisibility() }
        }

        refreshTask = Task { await refreshLoop() }
        Task { await lookaheadLoop() }
        Task { await loadTeams() }
        alerts.start()
        if ProcessInfo.processInfo.environment["GRIDIRON_DEBUG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.settings.show() }
        }
        if ProcessInfo.processInfo.environment["GRIDIRON_CHECK_NOW"] != nil {   // test the manual check path
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.checkForUpdates() }
        }
    }

    // MARK: Layout

    @objc private func layoutPanel() {
        guard let screen = Displays.target else { return }
        settings.syncDisplays()   // monitors may have just been plugged in or removed
        let vf = screen.visibleFrame
        let y = Prefs.atTop ? vf.maxY - barHeight : vf.minY
        panel.setFrame(NSRect(x: screen.frame.minX, y: y, width: screen.frame.width, height: barHeight), display: true)
        ticker.frame = NSRect(x: 0, y: 0, width: screen.frame.width, height: barHeight)
    }

    /// Text size and opacity from Settings.
    private func applyLook() {
        LogoStore.shared.configure(fontSize: Prefs.fontPoints)
        ticker.barOpacity = CGFloat(Prefs.barOpacity)
    }

    // MARK: Visibility and the menu bar score

    /// Whether the bar should be up for auto-hide: a followed team is playing or about to.
    private func followedGameIsOn() -> Bool {
        let followed = Prefs.followedIDs
        guard !followed.isEmpty else { return true }   // nothing to wait for: never hide
        return games.contains { g in
            guard followed.contains(g.away.teamID) || followed.contains(g.home.teamID) else { return false }
            return g.state == .live || (g.state == .upcoming && g.start.timeIntervalSinceNow <= 30 * 60)
        }
    }

    private func updateVisibility() {
        var show = !Prefs.hidden
        if Prefs.autoHide {
            let on = followedGameIsOn()
            if on { forceShown = false } else { forceHidden = false }
            show = (on && !forceHidden) || forceShown
        }
        if show != panel.isVisible {
            if show { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        }
    }

    /// The game to show in the menu bar: a followed team's live game, else its game today, else its final.
    private func menuBarGame() -> Game? {
        let followed = Prefs.followedIDs
        for pass in [GameState.live, .upcoming, .final] {
            for id in followed {
                if let g = games.first(where: { g in
                    g.involves(id) && g.state == pass
                        && (pass != .upcoming || Calendar.current.isDateInToday(g.start))
                        && (pass != .final || g.start.timeIntervalSinceNow > -12 * 3600)
                }) { return g }
            }
        }
        return nil
    }

    private func menuBarText(_ g: Game) -> String {
        func name(_ s: Side) -> String { s.abbr ?? s.name }
        func pts(_ s: Side) -> String { s.score ?? "0" }
        if g.scoresHidden { return "\(name(g.away)) @ \(name(g.home))  " + (g.state == .live ? "Live" : "Final") }
        switch g.state {
        case .live:
            let when = g.isHalftime ? "Half" : g.detail.replacingOccurrences(of: " - ", with: " ")
            return "\(name(g.away)) \(pts(g.away))–\(pts(g.home)) \(name(g.home))  \(when)"
        case .upcoming:
            return "\(name(g.away)) @ \(name(g.home))  \(g.detail)"
        case .final:
            return "\(name(g.away)) \(pts(g.away))–\(pts(g.home)) \(name(g.home))  " + g.detail.replacingOccurrences(of: "Final", with: "F")
        }
    }

    private func menuBarTitle() -> String {
        let fp = FantasyPrefs.menuBar ? FantasyStore.shared.menuBarText : ""
        if Prefs.menuBarScore, let g = menuBarGame() { return " " + menuBarText(g) + (fp.isEmpty ? "" : "  " + fp) }
        if !fp.isEmpty { return " " + fp }
        let live = games.filter { $0.state == .live }.count
        return live > 0 ? " \(live)" : ""
    }

    // MARK: Data

    private func refreshLoop() async {
        var first = true
        while !Task.isCancelled {
            let quick = quickRefreshGame()
            if let g = quick, Date().timeIntervalSince(lastFullRefresh) < 120 {
                // Only-my-team mode during a game: fetch just that game's day, every 10 seconds.
                if let day = try? await ESPN.fetchBoard(on: g.start),
                   let fresh = day.first(where: { $0.id == g.id }),
                   let i = games.firstIndex(where: { $0.id == g.id }) {
                    games[i] = fresh
                    lastUpdate = Date()
                    lastError = nil
                }
            } else {
                do {
                    games = try await ESPN.fetchToday()
                    lastUpdate = Date()
                    lastFullRefresh = Date()
                    lastError = nil
                } catch {
                    lastError = error.localizedDescription
                }
            }
            guard !Task.isCancelled else { return }
            slowDownUntil = Date().addingTimeInterval(TimeInterval(await ESPN.cooldownRemaining()))
            for fav in Prefs.followedIDs {
                for g in games where g.involves(fav) { alerts.observe(g, favoriteID: fav) }
            }
            alerts.remind(games + (lookahead.first ?? []), followed: Set(Prefs.followedIDs))
            await FantasyStore.shared.refresh(games: games, next: lookahead.first ?? [], week: await ESPN.currentWeek())
            render()
            ticker.flash(scoreChanges())
            if first, !games.isEmpty { ticker.resetToStart(); first = false }
            let anyLive = games.contains { $0.state == .live }
            let wait = quickRefreshGame() != nil ? 10 : (anyLive ? 20 : 120)
            try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
        }
    }

    /// Live games that should glow this refresh, per the "Flash score changes" setting.
    private func scoreChanges() -> Set<String> {
        var out = Set<String>()
        for g in games where g.state == .live && !g.scoresHidden {
            if let prev = lastLive[g.id],
               shouldFlash(prev: prev, now: g, mode: Prefs.flashMode, followed: Set(Prefs.followedIDs)) {
                out.insert(g.id)
            }
            lastLive[g.id] = g
        }
        return out
    }

    /// In only-my-team mode, the favorite's game today if it's live or about to kick off.
    private func quickRefreshGame() -> Game? {
        guard Prefs.favoriteOnly, let g = favoriteGame(), games.contains(where: { $0.id == g.id }) else { return nil }
        if g.state == .live { return g }
        let untilTip = g.start.timeIntervalSinceNow
        return g.state == .upcoming && untilTip < 5 * 60 && untilTip > -3 * 3600 ? g : nil
    }

    /// Restart the refresh loop so a new mode takes effect now rather than after its current sleep.
    private func restartRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { await refreshLoop() }
    }

    private func lookaheadLoop() async {
        var first = true
        while true {
            lookahead = await ESPN.fetchLookahead()
            await refreshScheduleNext()
            render()
            // On launch, a favorite that isn't playing today only appears once lookahead arrives.
            if first, Prefs.favoriteTeamID != nil { ticker.resetToStart() }
            first = false
            try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
        }
    }

    private func refreshScheduleNext() async {
        var out: [String: Game] = [:]
        for id in Prefs.followedIDs { if let g = try? await ESPN.fetchNextGame(teamID: id) { out[id] = g } }
        scheduleNext = out
    }

    private func loadTeams() async {
        for attempt in 0..<5 {
            if let t = try? await ESPN.fetchTeams(), !t.isEmpty {
                settings.setTeams(t)
                for team in t { teamColors[team.id] = (team.color, team.altColor); teamNameByID[team.id] = team.name }
                render()
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(10 + attempt * 20) * 1_000_000_000)
        }
    }

    /// Builds the ticker's game list: favorite first, then live, upcoming, finals.
    private func visibleGames() -> [Game] {
        var list = games
        if !Prefs.showFinals { list = list.filter { $0.state != .final } }
        if !Prefs.showUpcoming { list = list.filter { $0.state != .upcoming } }

        var ids = Set(list.map { $0.id })
        if Prefs.showUpcoming {
            // Nothing left to play today: show the next day that has games.
            if !games.contains(where: { $0.state != .final }),
               let day = lookahead.first(where: { !$0.isEmpty }) {
                for g in day where ids.insert(g.id).inserted {
                    list.append(g)
                }
            }
        }

        // Channel filter: live and upcoming games only, and never your followed teams' games.
        if !Prefs.channelFilter.isEmpty {
            let allowed = Set(Prefs.channelFilter.map { $0.lowercased() })
            let followed = Prefs.followedIDs
            list = list.filter { g in
                g.state == .final || allowed.contains((g.network ?? "").lowercased())
                    || followed.contains { g.involves($0) }
            }
        }

        // Upsets brewing, then close finishes, then other live games, upcoming, finals.
        func order(_ g: Game) -> Int {
            switch g.state {
            case .live:
                if Prefs.showAlertTags && !g.scoresHidden {
                    if g.isUpsetBrewing { return 0 }
                    if g.isCloseLate { return 1 }
                }
                return Prefs.showMarquee && g.isMarquee ? 2 : 3
            case .upcoming: return 4
            case .final: return 5
            }
        }
        list.sort {
            if order($0) != order($1) { return order($0) < order($1) }
            if $0.state == .upcoming, $0.start != $1.start { return $0.start < $1.start }
            return $0.start < $1.start
        }

        // Followed teams lead, in the order you picked them: favorite first, then the others.
        var lead: [Game] = []
        for id in Prefs.followedIDs {
            if let g = followedGame(id), !lead.contains(where: { $0.id == g.id }) { lead.append(g) }
        }
        list.removeAll { g in lead.contains { $0.id == g.id } }
        return lead + list
    }

    /// Favorite's game: today's (live > upcoming > final), else its soonest upcoming game
    /// from either the next few days' scoreboards or its season schedule.
    private func favoriteGame() -> Game? {
        guard let fav = Prefs.favoriteTeamID else { return nil }
        return followedGame(fav)
    }

    private func followedGame(_ fav: String) -> Game? {
        let today = games.filter { $0.involves(fav) }
        if let g = today.first(where: { $0.state == .live }) ?? today.first(where: { $0.state == .upcoming }) {
            return g
        }
        if let f = today.first(where: { $0.state == .final }) { return f }
        let candidates = lookahead.joined().filter { $0.involves(fav) } + [scheduleNext[fav]].compactMap { $0 }
        return candidates.filter { $0.state == .upcoming }.min { $0.start < $1.start }
    }

    private func render() {
        ticker.speed = CGFloat(Prefs.speed)
        let list = visibleGames()
        shownGames = list
        let defaultAccent = NSColor(calibratedWhite: 0.25, alpha: 1)
        if Prefs.favoriteOnly, Prefs.useTeamColors, let fav = Prefs.favoriteTeamID,
           let c = teamColors[fav], let bar = teamBarColors(primary: c.0, alternate: c.1) {
            ticker.setColors(background: bar.background, accent: bar.accent, accentHeight: 3)
        } else {
            ticker.setColors(background: .black, accent: defaultAccent, accentHeight: 1)
        }
        let fan = FantasyStore.shared.segments(font: font)
        if FantasyPrefs.display == 2 {
            shownGames = []
            if fan.segments.isEmpty {
                ticker.setCentered(NSAttributedString(string: "ADD PLAYERS UNDER FANTASY TEAM… IN THE MENU", attributes: [.font: font, .foregroundColor: Palette.dim]))
            } else {
                ticker.set(fan.segments, keys: fan.keys)
            }
        } else if Prefs.favoriteOnly, Prefs.favoriteTeamID != nil {
            shownGames = []
            let favOnBye = Prefs.favoriteTeamID.map { id in ESPN.byeTeamIDs.contains(id) && !games.contains { $0.involves(id) } } ?? false
            if !favOnBye, let g = favoriteGame() {
                shownGames = [g]
                ticker.setCentered(buildTickerSegments([g], followed: Set(Prefs.followedIDs), font: font, separator: false)[0], key: g.id)
            } else {
                let name = (Prefs.favoriteTeamName ?? "your team").uppercased()
                let onBye = Prefs.favoriteTeamID.map { ESPN.byeTeamIDs.contains($0) } ?? false
                let msg = onBye ? "\(name) · BYE WEEK" : (lookahead.isEmpty ? "LOADING \(name)…" : "NO UPCOMING GAME FOR \(name)")
                ticker.setCentered(NSAttributedString(string: msg, attributes: [.font: font, .foregroundColor: Palette.dim]))
            }
        } else {
            // A followed team on a bye gets its own "BYE WEEK" entry at the front.
            let byes = Prefs.followedIDs.filter { id in ESPN.byeTeamIDs.contains(id) && !games.contains { $0.involves(id) } }
            var segments = buildTickerSegments(list, followed: Set(Prefs.followedIDs), font: font)
            var keys = list.map { $0.id }
            for id in byes.reversed() {
                let name = (teamNameByID[id] ?? "TEAM").uppercased()
                let t = NSMutableAttributedString()
                t.append(NSAttributedString(string: "★ \(name)", attributes: [.font: font, .foregroundColor: Palette.favorite]))
                t.append(NSAttributedString(string: "  BYE WEEK      ◆      ", attributes: [.font: font, .foregroundColor: Palette.dim]))
                segments.insert(t, at: 0)
                keys.insert("bye-\(id)", at: 0)
            }
            if FantasyPrefs.display == 1 {
                segments = fan.segments + segments
                keys = fan.keys + keys
            } else if FantasyPrefs.display == 3 {
                segments += fan.segments
                keys += fan.keys
            }
            ticker.set(segments, keys: keys)
        }
        if ProcessInfo.processInfo.environment["GRIDIRON_DEBUG"] != nil {
            print("--- render: \(list.count) games, lookahead days loaded: \(lookahead.filter { !$0.isEmpty }.count)")
            for g in list.prefix(200) {
                print(" ", g.state, g.away.name, "@", g.home.name, "|", g.detail)
            }
            fflush(stdout)
        }
        boxPopover.update(with: games)
        statusItem.button?.title = menuBarTitle()
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.button?.toolTip = Prefs.menuBarScore ? menuBarGame().map(menuBarText) : nil
        updateVisibility()
        var channels = Set(Prefs.channelFilter)
        for g in games + lookahead.joined() { if let n = g.network { channels.insert(n) } }
        if channels != knownChannels { knownChannels = channels; settings.setChannels(channels.sorted()) }
        settings.sync()
    }

    /// A game on the ticker was clicked: show its box score, or go straight to ESPN, per the setting.
    private func gameClicked(at i: Int, x: CGFloat) {
        guard shownGames.indices.contains(i) else { return }
        let g = shownGames[i]
        if Prefs.clickAction == 1 { openESPN(g); return }
        if boxPopover.shownGameID == g.id { boxPopover.close(); return }   // click again to close
        boxPopover.show(g, in: ticker, at: x, below: Prefs.atTop)
    }

    /// ESPN's page for a game: live gamecast, box score, or preview.
    private func openESPN(_ g: Game) {
        guard let url = URL(string: "https://www.espn.com/nfl/game/_/gameId/\(g.id)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func settingChanged(_ change: SettingChange) {
        switch change {
        case .position:
            layoutPanel()
            ticker.needsLayout = true
        case .display:
            render()
        case .look:
            layoutPanel()
            applyLook()
            render()
        case .visibility:
            forceShown = false
            forceHidden = false
            updateVisibility()
        case .favoriteOnly:
            render()
            restartRefreshLoop()
        case .favorite, .followed:
            scheduleNext = scheduleNext.filter { Prefs.followedIDs.contains($0.key) }
            render()
            ticker.resetToStart()
            Task {
                await refreshScheduleNext()
                render()
                ticker.resetToStart()
            }
            restartRefreshLoop()   // the "also show followed teams' games" fetch depends on who's followed
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let live = games.filter { $0.state == .live }.count
        let up = games.filter { $0.state == .upcoming }.count
        let fin = games.filter { $0.state == .final }.count
        var status = "Today: \(live) live · \(up) upcoming · \(fin) final"
        if let e = lastError, lastUpdate == nil { status = "Can't reach ESPN (\(e))" }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        let slow = Int(slowDownUntil.timeIntervalSinceNow.rounded(.up))
        if slow > 0 {
            menu.addItem(withTitle: "ESPN asked us to slow down; retrying in \(slow) s", action: nil, keyEquivalent: "").isEnabled = false
        }
        if let t = lastUpdate {
            let f = DateFormatter(); f.timeStyle = .medium
            menu.addItem(withTitle: "Updated \(f.string(from: t))", action: nil, keyEquivalent: "").isEnabled = false
        }
        if let name = Prefs.favoriteTeamName {
            let more = Prefs.extraTeamIDs.filter { $0 != Prefs.favoriteTeamID }.count
            menu.addItem(withTitle: "★ Following \(name)" + (more > 0 ? " + \(more) more" : ""), action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(item("Show Only \(name)", #selector(toggleFavoriteOnly), checked: Prefs.favoriteOnly))
        }
        menu.addItem(.separator())

        menu.addItem(item("Spoiler-Free Mode", #selector(toggleSpoilerFree), checked: Prefs.spoilerMode != 0))
        menu.addItem(item(panel.isVisible ? "Hide Ticker" : "Show Ticker", #selector(toggleTicker)))
        menu.addItem(item("Refresh Now", #selector(refreshNow)))
        menu.addItem(item("Fantasy Team…", #selector(openFantasy), key: "f"))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(.separator())

        menu.addItem(item("Quit Gridiron Ticker Pro", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        it.state = checked ? .on : .off
        return it
    }

    @objc private func toggleSpoilerFree() {
        Prefs.spoilerMode = Prefs.spoilerMode == 0 ? 1 : 0   // on = my teams' games; pick "All games" in Settings
        render()
        settings.sync()
    }
    @objc private func toggleTicker() {
        if Prefs.autoHide {
            // Override just this stretch: the bar's own rule takes over again next game.
            let on = followedGameIsOn()
            if panel.isVisible { if on { forceHidden = true }; forceShown = false }
            else { if on { forceHidden = false } else { forceShown = true } }
        } else {
            Prefs.hidden = panel.isVisible
        }
        updateVisibility()
    }
    @objc private func refreshNow() {
        Task {
            if let g = try? await ESPN.fetchToday() {
                games = g; lastUpdate = Date(); lastError = nil
            }
            lookahead = await ESPN.fetchLookahead()
            await refreshScheduleNext()
            render()
        }
    }
    @objc private func openSettings() { settings.show() }
    @objc private func openFantasy() { fantasyWindow.show() }
    @objc private func checkForUpdates() { UpdateService.shared.checkForUpdates() }
    @objc private func toggleFavoriteOnly() {
        Prefs.favoriteOnly.toggle()
        settingChanged(.favoriteOnly)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
