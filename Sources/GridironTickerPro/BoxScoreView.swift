import AppKit

/// A button that works on the first click even though the app is never frontmost.
private final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The small popup that opens when you click a game on the ticker: score, team stats,
/// top scorers and (for a live game) the latest play. Refreshes every 15 seconds while a game is live.
@MainActor
final class BoxScorePopover: NSObject {
    private let popover = NSPopover()
    private var game: Game?
    private var box: BoxScore?
    private var failed = false
    private var loop: Task<Void, Never>?
    private var monitor: Any?

    /// Open the game's ESPN page.
    var onOpenESPN: ((Game) -> Void)?
    /// Called with true when the popup opens and false when it closes (the ticker holds still while it's open).
    var onVisibility: ((Bool) -> Void)?

    var isShown: Bool { popover.isShown }
    var shownGameID: String? { popover.isShown ? game?.id : nil }

    override init() {
        super.init()
        popover.behavior = .applicationDefined   // we close it ourselves: a click away, or on the ticker again
        popover.animates = false
    }

    /// Extra lines under a game stats (your fantasy players in it).
    var extraLines: ((Game) -> [String])?
    /// A team's (primary, alternate) color hex, for tinting the popup.
    var teamColors: ((String) -> (String?, String?)?)?
    private var logoRetries = 0

    func show(_ game: Game, in view: NSView, at x: CGFloat, below: Bool) {
        close()
        self.game = game
        box = nil
        failed = false
        logoRetries = 0
        popover.contentViewController = NSViewController()
        popover.contentViewController!.view = NSView()
        render()
        popover.show(relativeTo: NSRect(x: x - 1, y: 0, width: 2, height: view.bounds.height), of: view,
                     preferredEdge: below ? .minY : .maxY)
        onVisibility?(true)
        // A click anywhere outside this app closes it (clicks on the ticker itself are handled there).
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        guard game.state != .upcoming, !game.scoresHidden else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let id = self.game?.id else { return }
                do { self.box = try await ESPN.fetchBoxScore(gameID: id); self.failed = false }
                catch { if self.box == nil { self.failed = true } }
                if Task.isCancelled { return }
                self.render()
                guard self.game?.state == .live else { return }
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
            }
        }
    }

    func close() {
        loop?.cancel()
        loop = nil
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if popover.isShown { popover.performClose(nil); onVisibility?(false) }
    }

    /// The ticker has newer data for the game that's open.
    func update(with games: [Game]) {
        guard popover.isShown, let id = game?.id, let g = games.first(where: { $0.id == id }) else { return }
        game = g
        render()
    }

    /// A headshot finished downloading.
    func refreshIfShown() { if popover.isShown { render() } }

    // MARK: Content

    private func render() {
        guard let game, let host = popover.contentViewController?.view else { return }
        host.subviews.forEach { $0.removeFromSuperview() }

        func text(_ s: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
            let t = NSTextField(wrappingLabelWithString: s)
            t.font = .systemFont(ofSize: size, weight: weight)
            t.textColor = color
            t.preferredMaxLayoutWidth = 300
            return t
        }
        func name(_ s: Side) -> String {
            s.name
        }
        func abbr(_ s: Side) -> String { s.abbr ?? s.name }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Scoreboard header: logos, records, scores and a status pill, tinted with both teams' colors.
        let header = BoxHeaderView()
        header.game = game
        let awayHex = teamColors?(game.away.teamID), homeHex = teamColors?(game.home.teamID)
        header.awayColor = boxAccent(awayHex)
        header.homeColor = boxAccent(homeHex)
        header.awayLogo = LogoStore.shared.attachment(for: game.away.teamID, abbr: game.away.abbr, font: .systemFont(ofSize: 12))?.image
        header.homeLogo = LogoStore.shared.attachment(for: game.home.teamID, abbr: game.home.abbr, font: .systemFont(ofSize: 12))?.image
        if header.awayLogo == nil || header.homeLogo == nil, logoRetries < 4 {
            logoRetries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in if self?.popover.isShown == true { self?.render() } }
        }
        stack.addArrangedSubview(header)
        if game.state == .live, !game.scoresHidden, let s = game.situation {
            let ball = s.possessionID == game.home.teamID ? game.home : game.away
            if !s.text.isEmpty {
                stack.addArrangedSubview(text("\(s.text) · \(ball.name) ball" + (s.isRedZone ? " · RED ZONE" : ""),
                                              size: 13, weight: .semibold, color: Palette.rank))
            }
            let field = FieldView()
            field.away = abbr(game.away); field.home = abbr(game.home)
            field.situation = s
            field.awayHasBall = ball.teamID == game.away.teamID
            stack.addArrangedSubview(field)
            func dots(_ n: Int?) -> String { String(repeating: "●", count: max(0, min(3, n ?? 0))) + String(repeating: "○", count: 3 - max(0, min(3, n ?? 0))) }
            stack.addArrangedSubview(text("Timeouts   \(abbr(game.away)) \(dots(s.awayTimeouts))   \(abbr(game.home)) \(dots(s.homeTimeouts))",
                                          color: .secondaryLabelColor))
            if let play = s.lastPlay, !play.isEmpty {
                stack.addArrangedSubview(text("Last play", size: 11, weight: .semibold, color: .secondaryLabelColor))
                stack.addArrangedSubview(text(play))
            }
        }
        // Stats and leaders
        if game.scoresHidden {
            stack.addArrangedSubview(text("Scores are hidden (spoiler-free mode).", color: .secondaryLabelColor))
        } else if game.state != .upcoming {
            if let box, let a = box.lines[game.away.teamID], let h = box.lines[game.home.teamID], !a.stats.isEmpty {
                let bars = StatBarsView()
                bars.awayColor = boxAccent(awayHex)
                bars.homeColor = boxAccent(homeHex)
                bars.awayName = abbr(game.away); bars.homeName = abbr(game.home)
                bars.rows = a.stats.enumerated().map { i, s in
                    StatBarsView.Row(label: s.label, away: s.value, home: h.stats.indices.contains(i) ? h.stats[i].value : "–")
                }
                stack.addArrangedSubview(bars)
                let cards = LeaderCardsView()
                cards.groups = [(game.away, a, boxAccent(awayHex)), (game.home, h, boxAccent(homeHex))].compactMap { side, line, color in
                    guard !line.leaders.isEmpty else { return nil }
                    let items = line.leaders.enumerated().map { n, l -> LeaderCardsView.Card in
                        let parts = l.components(separatedBy: "  ")
                        let id = line.leaderIDs.indices.contains(n) ? line.leaderIDs[n] : ""
                        return LeaderCardsView.Card(kind: line.leaderKinds.indices.contains(n) ? line.leaderKinds[n] : "",
                                                    name: parts.first ?? l, detail: parts.dropFirst().joined(separator: "  "),
                                                    photo: PlayerPhotos.shared.image(for: id))
                    }
                    return (abbr(side), color, items)
                }
                stack.addArrangedSubview(cards)
                if game.state == .live, game.situation?.lastPlay == nil, let play = box.lastPlay {
                    stack.addArrangedSubview(text("Last play", size: 11, weight: .semibold, color: .secondaryLabelColor))
                    stack.addArrangedSubview(text(play))
                }
            } else if failed {
                stack.addArrangedSubview(text("The box score isn't available right now.", color: .secondaryLabelColor))
            } else {
                stack.addArrangedSubview(text("Loading box score…", color: .secondaryLabelColor))
            }
        }

        if game.state != .upcoming, !game.scoresHidden, let extra = extraLines?(game), !extra.isEmpty {
            stack.addArrangedSubview(text("Your fantasy players", size: 11, weight: .semibold, color: .secondaryLabelColor))
            for l in extra { stack.addArrangedSubview(text(l, color: Palette.favorite)) }
        }

        let button = FirstClickButton(title: "Open on ESPN", target: self, action: #selector(openESPN))
        button.bezelStyle = .rounded
        stack.addArrangedSubview(button)

        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            stack.widthAnchor.constraint(equalToConstant: 340),
        ])
        host.layoutSubtreeIfNeeded()
        let size = NSSize(width: 340, height: stack.fittingSize.height)
        host.setFrameSize(size)
        popover.contentSize = size
    }

    @objc private func openESPN() {
        guard let game else { return }
        close()
        onOpenESPN?(game)
    }
}
