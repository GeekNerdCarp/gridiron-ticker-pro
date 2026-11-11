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

    func show(_ game: Game, in view: NSView, at x: CGFloat, below: Bool) {
        close()
        self.game = game
        box = nil
        failed = false
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

        // Headline and status
        if game.state == .upcoming || game.scoresHidden {
            stack.addArrangedSubview(text("\(name(game.away)) @ \(name(game.home))", size: 15, weight: .semibold))
        } else {
            stack.addArrangedSubview(text("\(name(game.away))  \(game.away.score ?? "0")", size: 15, weight: .semibold))
            stack.addArrangedSubview(text("\(name(game.home))  \(game.home.score ?? "0")", size: 15, weight: .semibold))
        }
        let statusText = game.scoresHidden ? (game.state == .live ? "LIVE" : "FINAL")
            : (game.state == .live ? "LIVE · " + game.detail : game.detail)
        let status = [statusText, game.round, game.network]
            .compactMap { $0 }.joined(separator: " · ")
        stack.addArrangedSubview(text(status, color: game.state == .live ? Palette.live : .secondaryLabelColor))
        if game.state == .upcoming {
            let recs = [game.away, game.home].compactMap { s in s.record.map { "\(abbr(s)) \($0)" } }
            if !recs.isEmpty { stack.addArrangedSubview(text("Records: " + recs.joined(separator: "   "), color: .secondaryLabelColor)) }
        }

        // Stats and leaders
        if game.scoresHidden {
            stack.addArrangedSubview(text("Scores are hidden (spoiler-free mode).", color: .secondaryLabelColor))
        } else if game.state != .upcoming {
            if let box, let a = box.lines[game.away.teamID], let h = box.lines[game.home.teamID], !a.stats.isEmpty {
                let grid = NSGridView(views: [[NSTextField(labelWithString: ""), text(abbr(game.away), weight: .semibold),
                                               text(abbr(game.home), weight: .semibold)]]
                    + a.stats.enumerated().map { i, s in
                        [text(s.label, color: .secondaryLabelColor), text(s.value),
                         text(h.stats.indices.contains(i) ? h.stats[i].value : "–")]
                    })
                grid.columnSpacing = 14
                grid.rowSpacing = 4
                grid.column(at: 0).width = 40
                grid.column(at: 1).width = 70
                grid.column(at: 2).width = 70
                stack.addArrangedSubview(grid)
                for (side, line) in [(game.away, a), (game.home, h)] where !line.leaders.isEmpty {
                    stack.addArrangedSubview(text(abbr(side), size: 11, weight: .semibold, color: .secondaryLabelColor))
                    for l in line.leaders { stack.addArrangedSubview(text(l)) }
                }
                if game.state == .live, let play = box.lastPlay {
                    stack.addArrangedSubview(text("Last play", size: 11, weight: .semibold, color: .secondaryLabelColor))
                    stack.addArrangedSubview(text(play))
                }
            } else if failed {
                stack.addArrangedSubview(text("The box score isn't available right now.", color: .secondaryLabelColor))
            } else {
                stack.addArrangedSubview(text("Loading box score…", color: .secondaryLabelColor))
            }
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
