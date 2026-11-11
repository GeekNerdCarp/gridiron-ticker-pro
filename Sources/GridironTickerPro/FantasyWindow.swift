import AppKit

/// A single-column list of players with a title and optional buttons underneath.
@MainActor
private final class PlayerList: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let scroll = NSScrollView()
    let table = NSTableView()
    var players: [FantasyPlayer] = [] { didSet { table.reloadData() } }
    var points: ((FantasyPlayer) -> String?)?
    var onDouble: (() -> Void)?

    init(height: CGFloat) {
        super.init()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("p"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 20
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
    }
    @objc private func doubleClicked() { onDouble?() }
    var selected: FantasyPlayer? {
        let r = table.selectedRow
        return players.indices.contains(r) ? players[r] : nil
    }
    func numberOfRows(in tableView: NSTableView) -> Int { players.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let p = players[row]
        let extra = points?(p).map { "   \($0)" } ?? ""
        return "\(p.name)  ·  \(p.pos)  ·  \(p.teamAbbr)\(extra)"
    }
}

/// "Fantasy Team…": pick your players (and an opponent's), choose how it shows up, and look back at past weeks.
@MainActor
final class FantasyWindowController: NSObject, NSSearchFieldDelegate {
    private let window: NSWindow
    private let search = NSSearchField()
    private let results = PlayerList(height: 96)
    private let mine = PlayerList(height: 150)
    private let theirs = PlayerList(height: 150)
    private let status = NSTextField(labelWithString: "")
    private let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let menuBox = NSButton(checkboxWithTitle: "Show my fantasy total in the menu bar", target: nil, action: nil)
    private let alertBox = NSButton(checkboxWithTitle: "Alert me when my players score or are ruled out", target: nil, action: nil)
    private let thresholdPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let history = NSTextField(wrappingLabelWithString: "")
    private var pool: [FantasyPlayer] = []
    private var poolLoading = false
    private let thresholds = [0, 10, 15, 20, 25, 30]
    var onChange: (() -> Void)?
    private var centered = false

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
                          styleMask: [.titled, .closable], backing: .buffered, defer: true)
        super.init()
        window.title = "Fantasy Team"
        window.isReleasedWhenClosed = false
        build()
    }

    private func small(_ s: String) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = .systemFont(ofSize: 11)
        t.textColor = .secondaryLabelColor
        return t
    }
    private func bold(_ s: String) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = .systemFont(ofSize: 12, weight: .semibold)
        return t
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        return b
    }

    private func build() {
        search.placeholderString = "Search players (QB, RB, WR, TE)"
        search.delegate = self
        results.onDouble = { [weak self] in self?.addMine() }
        results.points = nil
        mine.points = { p in FantasyStore.shared.stats[p.id].map { "\(fantasyFormat($0.points)) pts" } }
        theirs.points = mine.points

        displayPopup.addItems(withTitles: ["Off", "Mixed in at the front of the ticker", "Only my fantasy team"])
        displayPopup.target = self; displayPopup.action = #selector(changed)
        menuBox.target = self; menuBox.action = #selector(changed)
        alertBox.target = self; alertBox.action = #selector(alertsToggled)
        thresholdPopup.addItems(withTitles: thresholds.map { $0 == 0 ? "No points alert" : "Alert at \($0) points" })
        thresholdPopup.target = self; thresholdPopup.action = #selector(changed)

        let addRow = NSStackView(views: [button("Add to my team", #selector(addMine)), button("Add to opponent", #selector(addTheirs))])
        addRow.spacing = 8

        let mineCol = NSStackView(views: [bold("My team"), mine.scroll, button("Remove selected", #selector(removeMine))])
        let theirCol = NSStackView(views: [bold("Opponent (optional, for a matchup line)"), theirs.scroll, button("Remove selected", #selector(removeTheirs))])
        for c in [mineCol, theirCol] { c.orientation = .vertical; c.alignment = .leading; c.spacing = 6 }
        let cols = NSStackView(views: [mineCol, theirCol])
        cols.distribution = .fillEqually
        cols.spacing = 16
        cols.alignment = .top

        let scoring = small("Scoring is ESPN standard: 1 point per 25 passing yards, 4 per passing TD, −2 per interception or lost fumble, 1 per 10 rushing or receiving yards, 6 per TD. Kickers, defenses and two-point conversions aren't counted.")
        history.font = .systemFont(ofSize: 11)
        history.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            bold("Find players"), search, results.scroll, addRow, status,
            cols, scoring,
            bold("Show it"), displayPopup, menuBox, alertBox, thresholdPopup,
            bold("Past weeks"), history,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(14, after: status)
        stack.setCustomSpacing(14, after: scoring)
        stack.setCustomSpacing(14, after: thresholdPopup)
        for v in [search, results.scroll, cols, scoring, history] {
            v.widthAnchor.constraint(equalToConstant: 540).isActive = true
        }
        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        window.contentView = root
        window.setContentSize(root.fittingSize)
    }

    func show() {
        sync()
        if !centered { window.center(); centered = true }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        loadPool()
    }

    /// Re-read the store (new stats arrived).
    func refresh() {
        mine.players = FantasyStore.shared.roster
        theirs.players = FantasyStore.shared.opponent
        renderHistory()
    }

    private func sync() {
        displayPopup.selectItem(at: FantasyPrefs.display)
        menuBox.state = FantasyPrefs.menuBar ? .on : .off
        alertBox.state = FantasyPrefs.alerts ? .on : .off
        thresholdPopup.selectItem(at: thresholds.firstIndex(of: FantasyPrefs.threshold) ?? 0)
        thresholdPopup.isEnabled = FantasyPrefs.alerts
        refresh()
    }

    private func loadPool() {
        guard pool.isEmpty, !poolLoading else { return }
        poolLoading = true
        status.stringValue = "Loading players from ESPN…"
        Task {
            let teams = (try? await ESPN.fetchTeams()) ?? []
            pool = await FantasyPool.load(teamIDs: teams.map { $0.id })
            poolLoading = false
            status.stringValue = pool.isEmpty ? "Couldn't reach ESPN for the player list. Close and reopen this window to try again." : ""
            filter()
        }
    }

    func controlTextDidChange(_ obj: Notification) { filter() }

    private func filter() {
        let q = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { results.players = []; return }
        let terms = q.split(separator: " ").map(String.init)
        results.players = Array(pool.filter { p in
            let hay = "\(p.name) \(p.teamAbbr) \(p.pos)".lowercased()
            return terms.allSatisfy { hay.contains($0) }
        }.prefix(60))
    }

    @objc private func addMine() { add(to: true) }
    @objc private func addTheirs() { add(to: false) }
    private func add(to mineList: Bool) {
        guard let p = results.selected else { status.stringValue = "Pick a player in the search results first."; return }
        let s = FantasyStore.shared
        let list = mineList ? s.roster : s.opponent
        guard !list.contains(p) else { status.stringValue = "\(p.name) is already on that list."; return }
        status.stringValue = ""
        if mineList { s.setRoster(list + [p]) } else { s.setOpponent(list + [p]) }
        refresh()
        onChange?()
    }
    @objc private func removeMine() {
        guard let p = mine.selected else { return }
        FantasyStore.shared.setRoster(FantasyStore.shared.roster.filter { $0 != p }); refresh(); onChange?()
    }
    @objc private func removeTheirs() {
        guard let p = theirs.selected else { return }
        FantasyStore.shared.setOpponent(FantasyStore.shared.opponent.filter { $0 != p }); refresh(); onChange?()
    }

    @objc private func changed() {
        FantasyPrefs.display = max(0, displayPopup.indexOfSelectedItem)
        FantasyPrefs.menuBar = menuBox.state == .on
        FantasyPrefs.threshold = thresholds[max(0, thresholdPopup.indexOfSelectedItem)]
        onChange?()
    }
    @objc private func alertsToggled() {
        guard alertBox.state == .on else { FantasyPrefs.alerts = false; thresholdPopup.isEnabled = false; return }
        TeamAlerts.requestPermission { [weak self] ok in
            FantasyPrefs.alerts = ok
            self?.alertBox.state = ok ? .on : .off
            self?.thresholdPopup.isEnabled = ok
        }
    }

    private func renderHistory() {
        let h = FantasyPrefs.history.sorted { $0.date > $1.date }
        guard !h.isEmpty else {
            history.stringValue = "Nothing yet. Each week's totals are saved here once your players' games start."
            return
        }
        var lines: [String] = []
        if let best = h.max(by: { $0.total < $1.total }) {
            lines.append("Best week: \(best.label) · \(fantasyFormat(best.total)) pts")
        }
        let wins = h.filter { $0.complete && ($0.opponent ?? .infinity) < $0.total }.count
        let losses = h.filter { $0.complete && ($0.opponent ?? -.infinity) > $0.total }.count
        if wins + losses > 0 { lines.append("Record against your opponents: \(wins)–\(losses)") }
        lines.append("")
        for r in h.prefix(12) {
            var l = "\(r.label): \(fantasyFormat(r.total)) pts"
            if let o = r.opponent { l += " vs \(fantasyFormat(o))" + (r.complete ? (r.total > o ? "  W" : (r.total < o ? "  L" : "  T")) : "") }
            if !r.complete { l += "  (in progress)" }
            lines.append(l)
        }
        history.stringValue = lines.joined(separator: "\n")
    }
}
