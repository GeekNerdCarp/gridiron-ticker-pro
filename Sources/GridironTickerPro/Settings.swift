import AppKit
import ServiceManagement

// MARK: - Stored preferences

enum Prefs {
    private static let d = UserDefaults.standard
    static var speed: Double {
        get { d.object(forKey: "speed") as? Double ?? 2.0 }
        set { d.set(newValue, forKey: "speed") }
    }
    static var rankedOnly: Bool {
        get { d.bool(forKey: "rankedOnly") }
        set { d.set(newValue, forKey: "rankedOnly") }
    }
    static var showFinals: Bool {
        get { d.object(forKey: "showFinals") as? Bool ?? true }
        set { d.set(newValue, forKey: "showFinals") }
    }
    static var showUpcoming: Bool {
        get { d.object(forKey: "showUpcoming") as? Bool ?? true }
        set { d.set(newValue, forKey: "showUpcoming") }
    }
    static var showRecords: Bool {
        get { d.object(forKey: "showRecords") as? Bool ?? true }
        set { d.set(newValue, forKey: "showRecords") }
    }
    /// When a ticker game glows after a score: 0 off, 1 my team, 2 big moments, 3 all games.
    static var flashMode: Int {
        get { d.object(forKey: "flashMode") as? Int ?? 1 }
        set { d.set(newValue, forKey: "flashMode") }
    }
    static let flashModes = ["Off", "My team scores", "Big moments", "All games"]
    /// Red "UPSET ALERT" / "CLOSE" tags on live games, which also move those games up.
    static var showAlertTags: Bool {
        get { d.object(forKey: "showAlertTags") as? Bool ?? true }
        set { d.set(newValue, forKey: "showAlertTags") }
    }
    static var showLogos: Bool {
        get { d.object(forKey: "showLogos") as? Bool ?? true }
        set { d.set(newValue, forKey: "showLogos") }
    }
    /// Hold the ticker still while the pointer is over it.
    static var pauseOnHover: Bool {
        get { d.object(forKey: "pauseOnHover") as? Bool ?? true }
        set { d.set(newValue, forKey: "pauseOnHover") }
    }
    /// Which display the ticker sits on (an NSScreenNumber), or nil to follow the main display.
    static var displayID: Int? {
        get { d.object(forKey: "displayID") as? Int }
        set { d.set(newValue, forKey: "displayID") }
    }
    static var atTop: Bool {
        get { d.bool(forKey: "atTop") }
        set { d.set(newValue, forKey: "atTop") }
    }
    static var hidden: Bool {
        get { d.bool(forKey: "hidden") }
        set { d.set(newValue, forKey: "hidden") }
    }
    static var favoriteTeamID: String? {
        get { d.string(forKey: "favoriteTeamID") }
        set { d.set(newValue, forKey: "favoriteTeamID") }
    }
    /// Up to `maxExtraTeams` more teams to follow, besides the favorite.
    static let maxExtraTeams = 5
    static var extraTeamIDs: [String] {
        get { d.stringArray(forKey: "extraTeamIDs") ?? [] }
        set { d.set(newValue, forKey: "extraTeamIDs") }
    }
    /// Every team that gets the ★ treatment: the favorite first, then the extras.
    static var followedIDs: [String] {
        var out: [String] = []
        for id in [favoriteTeamID].compactMap({ $0 }) + extraTeamIDs where !out.contains(id) { out.append(id) }
        return out
    }
    /// Only show games with a team from this conference (an ESPN group id); nil is all of Division I.
    static var conferenceID: Int? {
        get { d.object(forKey: "conferenceID") as? Int }
        set { d.set(newValue, forKey: "conferenceID") }
    }
    static var favoriteTeamName: String? {
        get { d.string(forKey: "favoriteTeamName") }
        set { d.set(newValue, forKey: "favoriteTeamName") }
    }

    /// Show just the favorite team's game, centered and not scrolling.
    static var favoriteOnly: Bool {
        get { d.bool(forKey: "favoriteOnly") }
        set { d.set(newValue, forKey: "favoriteOnly") }
    }

    /// Mac notifications for the favorite team's games.
    /// Alert on every score (touchdown, field goal…) in your team's games. On by default once notifications are on.
    static var notifyScores: Bool {
        get { d.object(forKey: "notifyScores") as? Bool ?? true }
        set { d.set(newValue, forKey: "notifyScores") }
    }
    static var notifyFavorite: Bool {
        get { d.bool(forKey: "notifyFavorite") }
        set { d.set(newValue, forKey: "notifyFavorite") }
    }

    /// In only-my-team mode, paint the bar in the team's colors.
    static var useTeamColors: Bool {
        get { d.object(forKey: "useTeamColors") as? Bool ?? true }
        set { d.set(newValue, forKey: "useTeamColors") }
    }

    /// Spoiler-free mode: 0 off, 1 hide scores of games with a team you follow, 2 hide every score.
    static var spoilerMode: Int {
        get { min(max(d.integer(forKey: "spoilerMode"), 0), 2) }
        set { d.set(newValue, forKey: "spoilerMode") }
    }
    /// Show ESPN's betting line (spread and over/under) on games that have one. Off unless you turn it on.
    static var showOdds: Bool {
        get { d.object(forKey: "showOdds") as? Bool ?? false }
        set { d.set(newValue, forKey: "showOdds") }
    }
    /// A gold MARQUEE badge on big matchups (two top-10 teams).
    static var showMarquee: Bool {
        get { d.object(forKey: "showMarquee") as? Bool ?? true }
        set { d.set(newValue, forKey: "showMarquee") }
    }
    /// Notify when a new AP poll comes out.
    static var pollAlerts: Bool {
        get { d.bool(forKey: "pollAlerts") }
        set { d.set(newValue, forKey: "pollAlerts") }
    }
    /// Ticker text size: an index into `textSizes`.
    static let textSizes: [(name: String, points: CGFloat)] = [("Small", 18), ("Medium", 22), ("Large", 26), ("Extra large", 32)]
    static var textSize: Int {
        get { min(max(d.object(forKey: "textSize") as? Int ?? 1, 0), textSizes.count - 1) }
        set { d.set(newValue, forKey: "textSize") }
    }
    static var fontPoints: CGFloat { textSizes[textSize].points }
    /// How solid the bar is, 0.4 (see-through) to 1.
    static var barOpacity: Double {
        get { min(max(d.object(forKey: "barOpacity") as? Double ?? 1.0, 0.4), 1.0) }
        set { d.set(newValue, forKey: "barOpacity") }
    }
    /// What clicking a game does: 0 opens a box score popup, 1 opens its ESPN page.
    static var clickAction: Int {
        get { d.integer(forKey: "clickAction") }
        set { d.set(newValue, forKey: "clickAction") }
    }
    /// Show the followed team's score in the menu bar item.
    static var menuBarScore: Bool {
        get { d.bool(forKey: "menuBarScore") }
        set { d.set(newValue, forKey: "menuBarScore") }
    }
    /// Hide the ticker unless a followed team's game is live or about to start.
    static var autoHide: Bool {
        get { d.bool(forKey: "autoHide") }
        set { d.set(newValue, forKey: "autoHide") }
    }
    /// Only show live and upcoming games on these channels (empty = every channel).
    static var channelFilter: [String] {
        get { d.stringArray(forKey: "channelFilter") ?? [] }
        set { d.set(newValue, forKey: "channelFilter") }
    }
    /// Minutes before tip-off to remind about a followed team's game (0 = off).
    static var reminderMinutes: Int {
        get { d.integer(forKey: "reminderMinutes") }
        set { d.set(newValue, forKey: "reminderMinutes") }
    }

    static let speeds: [(String, Double)] = [("Slow", 1.0), ("Medium", 2.0), ("Fast", 3.5)]
}

// MARK: - Displays

enum Displays {
    static func id(of screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }
    /// The chosen display, or nil if none is chosen or it isn't connected right now.
    static func screen(for id: Int?) -> NSScreen? {
        guard let id else { return nil }
        return NSScreen.screens.first { Displays.id(of: $0) == id }
    }
    /// Where the ticker goes: the chosen display if it's connected, otherwise the main one.
    static var target: NSScreen? { screen(for: Prefs.displayID) ?? NSScreen.main }
}

// MARK: - Open at login

/// Uses the system's login-item registration (macOS 13+), so it shows up in
/// System Settings › General › Login Items and the user can switch it off there too.
enum LoginItem {
    static var isSupported: Bool { if #available(macOS 13, *) { return true }; return false }

    static var isEnabled: Bool {
        guard #available(macOS 13, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns false if macOS refused, or needs the user to approve it in System Settings.
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        guard #available(macOS 13, *) else { return false }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            return false
        }
        return true
    }
}

// MARK: - Settings window

enum SettingChange { case favorite, followed, conference, favoriteOnly, position, display, visibility, look }

@MainActor
final class SettingsController: NSObject {
    var onChange: ((SettingChange) -> Void)?

    private let window: NSWindow
    private let teamPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let speedPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let extraPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    private let conferencePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let top25Popup = NSPopUpButton(frame: .zero, pullsDown: true)
    private let spoilerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let oddsBox = NSButton(checkboxWithTitle: "Show betting odds (spread and over/under)", target: nil, action: nil)
    private let marqueeBox = NSButton(checkboxWithTitle: "Marquee matchup tags (two top-10 teams)", target: nil, action: nil)
    private let pollBox = NSButton(checkboxWithTitle: "Notify me when the AP poll comes out", target: nil, action: nil)
    private let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let opacitySlider = NSSlider(value: 1, minValue: 0.4, maxValue: 1, target: nil, action: nil)
    private let opacityLabel = NSTextField(labelWithString: "100%")
    private let clickPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let reminderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let channelPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    private let menuScoreBox = NSButton(checkboxWithTitle: "Show my team's score in the menu bar", target: nil, action: nil)
    private let autoHideBox = NSButton(checkboxWithTitle: "Hide the bar unless my team is playing", target: nil, action: nil)
    private let reminderValues = [0, 15, 30, 60]
    private let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hoverBox = NSButton(checkboxWithTitle: "Pause while the pointer is over it", target: nil, action: nil)
    private let flashPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rankedBox = NSButton(checkboxWithTitle: "Top 25 games only", target: nil, action: nil)
    private let finalsBox = NSButton(checkboxWithTitle: "Final scores", target: nil, action: nil)
    private let upcomingBox = NSButton(checkboxWithTitle: "Upcoming games", target: nil, action: nil)
    private let recordsBox = NSButton(checkboxWithTitle: "Team records", target: nil, action: nil)
    private let logosBox = NSButton(checkboxWithTitle: "Team logos", target: nil, action: nil)
    private let tagsBox = NSButton(checkboxWithTitle: "Close-game tags", target: nil, action: nil)
    private let favoriteOnlyBox = NSButton(checkboxWithTitle: "Show only my team's game", target: nil, action: nil)
    private let colorsBox = NSButton(checkboxWithTitle: "Use my team's colors", target: nil, action: nil)
    private let scoresBox = NSButton(checkboxWithTitle: "Alert on every score", target: nil, action: nil)
    private let notifyBox = NSButton(checkboxWithTitle: "Notify me about my team's games", target: nil, action: nil)
    private let loginBox = NSButton(checkboxWithTitle: "Open Gridiron Ticker Pro when you log in", target: nil, action: nil)
    private let updatesBox = NSButton(checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)
    private var centered = false

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Gridiron Ticker Pro Settings"
        window.isReleasedWhenClosed = false

        positionPopup.addItems(withTitles: ["Bottom of screen", "Top of screen"])
        speedPopup.addItems(withTitles: Prefs.speeds.map { $0.0 })
        flashPopup.addItems(withTitles: Prefs.flashModes)
        teamPopup.addItem(withTitle: "Loading teams…")
        teamPopup.isEnabled = false
        extraPopup.addItem(withTitle: "Loading teams…")
        extraPopup.isEnabled = false
        conferencePopup.addItem(withTitle: "All Division I")
        top25Popup.addItem(withTitle: "Loading…")
        top25Popup.isEnabled = false
        spoilerPopup.addItems(withTitles: ["Off", "My teams' games only", "All games"])
        sizePopup.addItems(withTitles: Prefs.textSizes.map { $0.name })
        opacitySlider.isContinuous = true
        opacityLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        clickPopup.addItems(withTitles: ["Shows a box score", "Opens the ESPN page"])
        reminderPopup.addItems(withTitles: ["Off", "15 minutes before tip-off", "30 minutes before tip-off", "1 hour before tip-off"])
        channelPopup.addItem(withTitle: "All channels")
        channelPopup.isEnabled = false
        for c: NSControl in [teamPopup, conferencePopup, spoilerPopup, marqueeBox, oddsBox, pollBox, sizePopup, opacitySlider, clickPopup, reminderPopup, scoresBox, menuScoreBox, autoHideBox, favoriteOnlyBox, colorsBox, notifyBox, positionPopup, displayPopup, speedPopup, hoverBox, flashPopup, rankedBox, finalsBox, upcomingBox, recordsBox, logosBox, tagsBox, loginBox, updatesBox] {
            c.target = self
            c.action = #selector(changed(_:))
        }

        let hint = NSTextField(wrappingLabelWithString:
            "Your team's game shows first in the ticker: live, today's final, or its next scheduled game, even if that's days away.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let onlyHint = NSTextField(wrappingLabelWithString:
            "Holds that one game still in the middle of the ticker and updates the score every 10 seconds while it's live.")
        onlyHint.font = .systemFont(ofSize: 11)
        onlyHint.textColor = .secondaryLabelColor
        let notifyHint = NSTextField(wrappingLabelWithString: "Kickoff, halftime, overtime, a close finish, and the final score.")
        notifyHint.font = .systemFont(ofSize: 11)
        notifyHint.textColor = .secondaryLabelColor
        let notifyStack = NSStackView(views: [notifyBox, scoresBox, notifyHint])
        notifyStack.orientation = .vertical
        notifyStack.alignment = .leading
        notifyStack.spacing = 2
        let colorsRow = NSStackView(views: [colorsBox])
        colorsRow.edgeInsets = NSEdgeInsets(top: 2, left: 20, bottom: 0, right: 0)
        let onlyStack = NSStackView(views: [favoriteOnlyBox, onlyHint, colorsRow])
        onlyStack.orientation = .vertical
        onlyStack.alignment = .leading
        onlyStack.spacing = 2

        let flashLabel = NSTextField(labelWithString: "Flash score changes:")
        let flashRow = NSStackView(views: [flashLabel, flashPopup])
        flashRow.spacing = 6
        let flashHint = NSTextField(wrappingLabelWithString:
            "Big moments: lead changes, ties, and one-possession games in the last 4 minutes.")
        flashHint.font = .systemFont(ofSize: 11)
        flashHint.textColor = .secondaryLabelColor
        let showStack = NSStackView(views: [finalsBox, upcomingBox, logosBox, recordsBox, tagsBox, oddsBox, flashRow, flashHint])
        showStack.orientation = .vertical
        showStack.alignment = .leading
        showStack.spacing = 6

        func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }
        func small(_ text: String) -> NSTextField {
            let t = NSTextField(wrappingLabelWithString: text)
            t.font = .systemFont(ofSize: 11)
            t.textColor = .secondaryLabelColor
            return t
        }
        func stack(_ views: [NSView]) -> NSStackView {
            let v = NSStackView(views: views)
            v.orientation = .vertical; v.alignment = .leading; v.spacing = 2
            return v
        }
        let channelHint = small("Live and upcoming games only. Games for teams you follow always show.")
        let autoHideHint = small("The bar appears when a game is live or about to start. Use Show Ticker in the menu to see it any time.")
        let menuHint = small("Use Hide Ticker in the menu for a menu-bar-only ticker.")
        let opacityRow = NSStackView(views: [opacitySlider, opacityLabel])
        opacityRow.spacing = 8
        opacitySlider.widthAnchor.constraint(equalToConstant: 210).isActive = true
        opacityLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let spoilerHint = small("Hides the score, close-game and upset tags, and the box score for games you're recording. Alerts won't give away a result either.")
        let spoilerStack = stack([spoilerPopup, spoilerHint])
        let channelStack = stack([channelPopup, channelHint])
        let autoHideStack = stack([autoHideBox, autoHideHint])
        let menuStack = stack([menuScoreBox, menuHint])

        func page(_ rows: [[NSView]], topAlignedRow: Int? = nil) -> NSView {
            let grid = NSGridView(views: rows)
            grid.column(at: 0).xPlacement = .trailing
            grid.rowAlignment = .firstBaseline
            if let r = topAlignedRow { grid.row(at: r).rowAlignment = .none; grid.row(at: r).yPlacement = .top }
            grid.rowSpacing = 12
            grid.columnSpacing = 10
            grid.translatesAutoresizingMaskIntoConstraints = false
            let v = NSView()
            v.addSubview(grid)
            NSLayoutConstraint.activate([
                grid.topAnchor.constraint(equalTo: v.topAnchor, constant: 16),
                grid.bottomAnchor.constraint(lessThanOrEqualTo: v.bottomAnchor, constant: -16),
                grid.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
                grid.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -20),
            ])
            return v
        }
        let empty = NSGridCell.emptyContentView
        let teamsPage = page([
            [label("Follow your favorite team:"), teamPopup],
            [empty, hint],
            [label("Also follow:"), extraPopup],
            [empty, onlyStack],
            [empty, notifyStack],
            [label("Remind me:"), reminderPopup],
            [label("Only games on:"), channelStack],
        ], topAlignedRow: 6)
        let lookPage = page([
            [label("Position:"), positionPopup],
            [label("Display:"), displayPopup],
            [label("Scroll speed:"), speedPopup],
            [label("Text size:"), sizePopup],
            [label("Bar opacity:"), opacityRow],
            [empty, hoverBox],
            [label("Menu bar:"), menuStack],
            [label("Ticker bar:"), autoHideStack],
        ])
        let gamesPage = page([
            [label("Show:"), showStack],
            [label("Clicking a game:"), clickPopup],
            [label("Spoiler-free:"), spoilerStack],
        ], topAlignedRow: 0)
        let generalPage = page([
            [label("Startup:"), loginBox],
            [label("Updates:"), updatesBox],
        ])
        NSLayoutConstraint.activate([
            teamPopup.widthAnchor.constraint(equalToConstant: 280),
            extraPopup.widthAnchor.constraint(equalToConstant: 280),
            conferencePopup.widthAnchor.constraint(equalToConstant: 280),
            reminderPopup.widthAnchor.constraint(equalToConstant: 280),
            channelPopup.widthAnchor.constraint(equalToConstant: 280),
            top25Popup.widthAnchor.constraint(equalToConstant: 280),
            hint.widthAnchor.constraint(equalToConstant: 280),
            onlyHint.widthAnchor.constraint(equalToConstant: 280),
            notifyHint.widthAnchor.constraint(equalToConstant: 280),
            flashHint.widthAnchor.constraint(equalToConstant: 280),
            channelHint.widthAnchor.constraint(equalToConstant: 280),
            spoilerHint.widthAnchor.constraint(equalToConstant: 280),
            autoHideHint.widthAnchor.constraint(equalToConstant: 280),
            menuHint.widthAnchor.constraint(equalToConstant: 280),
        ])

        let tabs = NSTabView()
        for (title, view) in [("Teams", teamsPage), ("Ticker", lookPage), ("Games", gamesPage), ("General", generalPage)] {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = view
            tabs.addTabViewItem(item)
        }
        let sizes = [teamsPage, lookPage, gamesPage, generalPage].map { $0.fittingSize }
        tabs.setFrameSize(NSSize(width: (sizes.map { $0.width }.max() ?? 480) + 24,
                                 height: (sizes.map { $0.height }.max() ?? 300) + 56))
        window.contentView = tabs
        window.setContentSize(tabs.frame.size)
        sync()
    }

    private var teamNames: [String: String] = [:]

    /// The current AP poll, as a list to look through (nothing in it is clickable).
    func setTop25(_ teams: [RankedTeam]) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Current poll", action: nil, keyEquivalent: ""))   // the pull-down's title
        for t in teams {
            let rec = t.record.isEmpty ? "" : "  (\(t.record))"
            let it = NSMenuItem(title: String(format: "%2d  %@%@", t.rank, t.name, rec), action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        }
        top25Popup.menu = menu
        top25Popup.autoenablesItems = false
        top25Popup.isEnabled = true
    }

    /// The channels seen in today's data, for the "Only games on" menu.
    func setChannels(_ names: [String]) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))   // the pull-down's title
        let all = NSMenuItem(title: "All channels", action: #selector(channelsCleared), keyEquivalent: "")
        all.target = self
        menu.addItem(all)
        menu.addItem(.separator())
        for n in names {
            let it = NSMenuItem(title: n, action: #selector(channelToggled(_:)), keyEquivalent: "")
            it.target = self
            menu.addItem(it)
        }
        channelPopup.menu = menu
        channelPopup.isEnabled = true
        syncChannels()
    }

    private func syncChannels() {
        guard let menu = channelPopup.menu, menu.items.count > 3 else { return }
        let picked = Set(Prefs.channelFilter)
        for it in menu.items.dropFirst(3) { it.state = picked.contains(it.title) ? .on : .off }
        menu.items[0].title = picked.isEmpty ? "All channels"
            : (picked.count <= 2 ? picked.sorted().joined(separator: ", ") : "\(picked.count) channels")
    }

    @objc private func channelToggled(_ item: NSMenuItem) {
        var picked = Prefs.channelFilter
        if let i = picked.firstIndex(of: item.title) { picked.remove(at: i) } else { picked.append(item.title) }
        Prefs.channelFilter = picked
        syncChannels()
        onChange?(.display)
    }

    @objc private func channelsCleared() {
        Prefs.channelFilter = []
        syncChannels()
        onChange?(.display)
    }

    func setConferences(_ list: [Conference]) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "All Division I", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        for c in list {
            let it = NSMenuItem(title: c.name, action: nil, keyEquivalent: "")
            it.representedObject = c.id
            menu.addItem(it)
        }
        conferencePopup.menu = menu
        sync()
    }

    /// Check marks on the followed teams, and a title that says how many there are.
    private func syncExtras() {
        guard let menu = extraPopup.menu, menu.items.count > 1 else { return }
        let ids = Prefs.extraTeamIDs
        for it in menu.items.dropFirst() { it.state = ids.contains((it.representedObject as? String) ?? "") ? .on : .off }
        let names = ids.compactMap { teamNames[$0] }
        menu.items[0].title = names.isEmpty ? "None  (pick up to \(Prefs.maxExtraTeams))"
            : (names.count <= 2 ? names.joined(separator: ", ") : "\(names.count) teams")
    }

    func setTeams(_ teams: [TeamInfo]) {
        teamNames = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0.name) })
        let extra = NSMenu()
        extra.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))   // the pull-down's title
        for t in teams {
            let it = NSMenuItem(title: t.name, action: nil, keyEquivalent: "")
            it.representedObject = t.id
            it.target = self
            it.action = #selector(extraToggled(_:))
            extra.addItem(it)
        }
        extraPopup.menu = extra
        extraPopup.isEnabled = true
        syncExtras()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "None", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        for t in teams {
            let it = NSMenuItem(title: t.name, action: nil, keyEquivalent: "")
            it.representedObject = t.id
            menu.addItem(it)
        }
        teamPopup.menu = menu
        teamPopup.isEnabled = true
        sync()
    }

    /// Pull current values from Prefs into the controls.
    func sync() {
        if teamPopup.isEnabled {
            let fav = Prefs.favoriteTeamID
            let idx = teamPopup.itemArray.firstIndex { ($0.representedObject as? String) == fav && fav != nil } ?? 0
            teamPopup.selectItem(at: idx)
        }
        favoriteOnlyBox.state = Prefs.favoriteOnly ? .on : .off
        favoriteOnlyBox.isEnabled = Prefs.favoriteTeamID != nil
        colorsBox.state = Prefs.useTeamColors ? .on : .off
        colorsBox.isEnabled = Prefs.favoriteTeamID != nil && Prefs.favoriteOnly
        notifyBox.state = Prefs.notifyFavorite ? .on : .off
        scoresBox.state = Prefs.notifyScores ? .on : .off
        notifyBox.isEnabled = Prefs.favoriteTeamID != nil
        positionPopup.selectItem(at: Prefs.atTop ? 1 : 0)
        syncExtras()
        syncChannels()
        spoilerPopup.selectItem(at: Prefs.spoilerMode)
        marqueeBox.state = Prefs.showMarquee ? .on : .off
        oddsBox.state = Prefs.showOdds ? .on : .off
        pollBox.state = Prefs.pollAlerts ? .on : .off
        sizePopup.selectItem(at: Prefs.textSize)
        opacitySlider.doubleValue = Prefs.barOpacity
        opacityLabel.stringValue = "\(Int((Prefs.barOpacity * 100).rounded()))%"
        clickPopup.selectItem(at: Prefs.clickAction)
        reminderPopup.selectItem(at: reminderValues.firstIndex(of: Prefs.reminderMinutes) ?? 0)
        reminderPopup.isEnabled = !Prefs.followedIDs.isEmpty
        menuScoreBox.state = Prefs.menuBarScore ? .on : .off
        autoHideBox.state = Prefs.autoHide ? .on : .off
        autoHideBox.isEnabled = !Prefs.followedIDs.isEmpty
        let confIdx = conferencePopup.itemArray.firstIndex {
            ($0.representedObject as? Int) == Prefs.conferenceID && Prefs.conferenceID != nil
        } ?? 0
        conferencePopup.selectItem(at: confIdx)
        syncDisplays()
        hoverBox.state = Prefs.pauseOnHover ? .on : .off
        speedPopup.selectItem(at: Prefs.speeds.firstIndex { $0.1 == Prefs.speed } ?? 1)
        rankedBox.state = Prefs.rankedOnly ? .on : .off
        finalsBox.state = Prefs.showFinals ? .on : .off
        upcomingBox.state = Prefs.showUpcoming ? .on : .off
        recordsBox.state = Prefs.showRecords ? .on : .off
        tagsBox.state = Prefs.showAlertTags ? .on : .off
        logosBox.state = Prefs.showLogos ? .on : .off
        flashPopup.selectItem(at: Prefs.flashMode)
        updatesBox.state = UpdateService.shared.automaticallyChecks ? .on : .off
        loginBox.state = LoginItem.isEnabled ? .on : .off
        loginBox.isEnabled = LoginItem.isSupported
        if !LoginItem.isSupported { loginBox.title = "Open at login (needs macOS 13 or later)" }
    }

    /// Rebuild the display list (monitors come and go) and select the saved choice.
    func syncDisplays() {
        let menu = NSMenu()
        let auto = NSMenuItem(title: "Main display", action: nil, keyEquivalent: "")
        menu.addItem(auto)
        let screens = NSScreen.screens
        if screens.count > 1 {
            menu.addItem(.separator())
            for (i, sc) in screens.enumerated() {
                // Two identical monitors share a name, so number every entry.
                let it = NSMenuItem(title: "\(i + 1). \(sc.localizedName)", action: nil, keyEquivalent: "")
                it.representedObject = Displays.id(of: sc)
                menu.addItem(it)
            }
        }
        displayPopup.menu = menu
        displayPopup.isEnabled = screens.count > 1
        let saved = Prefs.displayID
        let idx = displayPopup.itemArray.firstIndex { ($0.representedObject as? Int) == saved && saved != nil } ?? 0
        displayPopup.selectItem(at: idx)
    }

    func show() {
        sync()
        if !centered { window.center(); centered = true }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// A team was picked in "Also follow": add it, or remove it if it was already followed.
    @objc private func extraToggled(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        var ids = Prefs.extraTeamIDs
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) }
        else if ids.count < Prefs.maxExtraTeams { ids.append(id) }
        else { NSSound.beep(); return }
        Prefs.extraTeamIDs = ids
        syncExtras()
        onChange?(.followed)
    }

    @objc private func changed(_ sender: NSControl) {
        switch sender {
        case teamPopup:
            let item = teamPopup.selectedItem
            let id = item?.representedObject as? String
            Prefs.favoriteTeamID = id
            Prefs.favoriteTeamName = id == nil ? nil : item?.title
            favoriteOnlyBox.isEnabled = id != nil
            notifyBox.isEnabled = id != nil
            onChange?(.favorite)
        case favoriteOnlyBox:
            Prefs.favoriteOnly = favoriteOnlyBox.state == .on
            colorsBox.isEnabled = Prefs.favoriteOnly
            onChange?(.favoriteOnly)
        case positionPopup:
            Prefs.atTop = positionPopup.indexOfSelectedItem == 1
            onChange?(.position)
        case spoilerPopup:
            Prefs.spoilerMode = max(0, spoilerPopup.indexOfSelectedItem)
            onChange?(.display)
        case oddsBox:
            Prefs.showOdds = oddsBox.state == .on
            onChange?(.display)
        case marqueeBox:
            Prefs.showMarquee = marqueeBox.state == .on
            onChange?(.display)
        case pollBox:
            guard pollBox.state == .on else { Prefs.pollAlerts = false; return }
            TeamAlerts.requestPermission { [weak self] ok in
                Prefs.pollAlerts = ok
                self?.pollBox.state = ok ? .on : .off
            }
        case sizePopup:
            Prefs.textSize = max(0, sizePopup.indexOfSelectedItem)
            onChange?(.look)
        case opacitySlider:
            let v = (opacitySlider.doubleValue * 20).rounded() / 20   // steps of 5%
            Prefs.barOpacity = v
            opacityLabel.stringValue = "\(Int((v * 100).rounded()))%"
            onChange?(.look)
        case clickPopup:
            Prefs.clickAction = max(0, clickPopup.indexOfSelectedItem)
        case reminderPopup:
            let mins = reminderValues[max(0, reminderPopup.indexOfSelectedItem)]
            Prefs.reminderMinutes = mins
            if mins > 0 {
                TeamAlerts.requestPermission { [weak self] ok in
                    guard !ok else { return }
                    Prefs.reminderMinutes = 0
                    self?.reminderPopup.selectItem(at: 0)
                }
            }
        case menuScoreBox:
            Prefs.menuBarScore = menuScoreBox.state == .on
            onChange?(.display)
        case autoHideBox:
            Prefs.autoHide = autoHideBox.state == .on
            onChange?(.visibility)
        case conferencePopup:
            Prefs.conferenceID = conferencePopup.selectedItem?.representedObject as? Int
            onChange?(.conference)
        case displayPopup:
            Prefs.displayID = displayPopup.selectedItem?.representedObject as? Int
            onChange?(.position)
        case speedPopup:
            Prefs.speed = Prefs.speeds[max(0, speedPopup.indexOfSelectedItem)].1
            onChange?(.display)
        case rankedBox:
            Prefs.rankedOnly = rankedBox.state == .on
            onChange?(.display)
        case finalsBox:
            Prefs.showFinals = finalsBox.state == .on
            onChange?(.display)
        case upcomingBox:
            Prefs.showUpcoming = upcomingBox.state == .on
            onChange?(.display)
        case hoverBox:
            Prefs.pauseOnHover = hoverBox.state == .on
        case colorsBox:
            Prefs.useTeamColors = colorsBox.state == .on
            onChange?(.display)
        case scoresBox:
            Prefs.notifyScores = scoresBox.state == .on
        case notifyBox:
            guard notifyBox.state == .on else { Prefs.notifyFavorite = false; return }
            TeamAlerts.requestPermission { [weak self] ok in
                Prefs.notifyFavorite = ok
                self?.notifyBox.state = ok ? .on : .off
            }
        case flashPopup:
            Prefs.flashMode = max(0, flashPopup.indexOfSelectedItem)
        case logosBox:
            Prefs.showLogos = logosBox.state == .on
            onChange?(.display)
        case tagsBox:
            Prefs.showAlertTags = tagsBox.state == .on
            onChange?(.display)
        case recordsBox:
            Prefs.showRecords = recordsBox.state == .on
            onChange?(.display)
        case loginBox:
            LoginItem.set(loginBox.state == .on)
            loginBox.state = LoginItem.isEnabled ? .on : .off   // reflect what macOS actually did
        case updatesBox:
            UpdateService.shared.automaticallyChecks = updatesBox.state == .on
        default:
            break
        }
    }
}
