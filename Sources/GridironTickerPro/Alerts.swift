import AppKit
@preconcurrency import UserNotifications

/// Watches the favorite team's game between refreshes and posts a Mac notification
/// when something happens: kickoff, scores, halftime, overtime, a close finish, and the final.
/// Only changes it actually sees fire, so relaunching mid-game doesn't replay old news.
@MainActor
final class TeamAlerts: NSObject, UNUserNotificationCenterDelegate {
    enum Event: Equatable { case kickoff, score(team: String, points: Int, total: Int), halftime, overtime, closeGame, final }

    private var last: [String: Game] = [:]          // game id -> previous snapshot
    private var sent: [String: Set<String>] = [:]   // game id -> events already posted

    /// Compare this refresh with the previous one. Returns what's newsworthy (for testing).
    @discardableResult
    func observe(_ g: Game, favoriteID: String) -> [Event] {
        defer { last[g.id] = g }
        guard let prev = last[g.id] else { return [] }
        var events: [Event] = []
        if prev.state == .upcoming && g.state == .live { events.append(.kickoff) }
        if Prefs.notifyScores, g.state == .live, !g.scoresHidden {
            for (before, now) in [(prev.away, g.away), (prev.home, g.home)] {
                if let b = Int(before.score ?? ""), let n = Int(now.score ?? ""), n > b {
                    events.append(.score(team: now.name, points: n - b, total: n))
                }
            }
        }
        if !prev.isHalftime && g.isHalftime { events.append(.halftime) }
        if prev.period < 5 && g.period >= 5 && g.state == .live { events.append(.overtime) }
        if g.isCloseLate && !g.scoresHidden { events.append(.closeGame) }
        if prev.state != .final && g.state == .final { events.append(.final) }

        var done = sent[g.id, default: []]
        events = events.filter { done.insert("\($0)").inserted }
        sent[g.id] = done
        if Prefs.notifyFavorite { events.forEach { post($0, g, favoriteID: favoriteID) } }
        return events
    }

    /// The notification text for an event. In spoiler-free mode it never includes a score or a result.
    func message(_ e: Event, _ g: Game, favoriteID: String) -> (title: String, body: String) {
        let mine = g.away.teamID == favoriteID ? g.away : g.home
        let other = g.away.teamID == favoriteID ? g.home : g.away
        func label(_ s: Side) -> String {
            (s.rank.map { "#\($0) " } ?? s.seed.map { "(\($0)) " } ?? "") + s.name
        }
        func score(_ s: Side) -> String { "\(s.name) \(s.score ?? "0")" }
        let line = "\(score(g.away)), \(score(g.home))"
        let tv = g.network.map { " · \($0)" } ?? ""
        let hidden = g.scoresHidden

        switch e {
        case .kickoff:
            return ("\(mine.name) kick off", "\(label(g.away)) @ \(label(g.home))\(tv)")
        case .score(let team, let points, _):
            let what: String
            switch points {
            case 6, 7, 8: what = "TOUCHDOWN"
            case 3: what = "FIELD GOAL"
            case 2: what = "SAFETY / 2-PT"
            case 1: what = "EXTRA POINT"
            default: what = "SCORE (+\(points))"
            }
            return ("\(what): \(team)", "\(line) · \(g.detail)")
        case .overtime:
            return ("Overtime!", hidden ? "Score hidden (spoiler-free mode)" : line)
        case .halftime:
            return ("Halftime", hidden ? "Score hidden (spoiler-free mode)" : line)
        case .closeGame:
            return ("Close game: \(mine.name) vs \(other.name)", "\(line) · \(g.detail)\(tv)")
        case .final:
            if hidden { return ("\(mine.name) game is over", "Score hidden (spoiler-free mode)") }
            let m = Int(mine.score ?? "") ?? 0, o = Int(other.score ?? "") ?? 0
            return (m > o ? "\(mine.name) wins!" : "\(mine.name) loses", "\(g.detail): \(line)")
        }
    }

    private func post(_ e: Event, _ g: Game, favoriteID: String) {
        let (title, body) = message(e, g, favoriteID: favoriteID)
        let content = UNMutableNotificationContent()
        content.title = "🏈 " + title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "\(g.id)-\(e)", content: content, trigger: nil))
    }

    // MARK: AP poll

    /// A new AP poll came out: say how your followed teams moved (or the top three, if none of them are in it).
    /// The first poll ever seen, a poll we already told you about, and a poll over four days old stay quiet.
    /// Returns the text sent, for testing.
    @discardableResult
    func observePoll(_ poll: AppPoll, followed: Set<String>, now: Date = Date()) -> (title: String, body: String)? {
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: "lastPollID")
        guard !poll.id.isEmpty else { return nil }
        defaults.set(poll.id, forKey: "lastPollID")
        guard let last, last != poll.id, Prefs.pollAlerts else { return nil }
        if let date = poll.date, now.timeIntervalSince(date) > 4 * 86400 { return nil }

        var lines: [String] = []
        for t in poll.teams where followed.contains(t.id) {
            let before = t.previous ?? 0
            if before == 0 { lines.append("\(t.name) enters the poll at #\(t.rank)") }
            else if before > t.rank { lines.append("\(t.name) moves up \(before - t.rank) to #\(t.rank)") }
            else if before < t.rank { lines.append("\(t.name) drops \(t.rank - before) to #\(t.rank)") }
            else { lines.append("\(t.name) holds at #\(t.rank)") }
        }
        for t in poll.dropped where followed.contains(t.id) { lines.append("\(t.name) falls out of the poll") }
        if lines.isEmpty {
            lines = [poll.teams.sorted { $0.rank < $1.rank }.prefix(3).map { "#\($0.rank) \($0.name)" }.joined(separator: " · ")]
        }
        let title = "🏈 New AP Top 25" + (poll.title.isEmpty ? "" : " · \(poll.title)")
        let body = lines.joined(separator: "\n")

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "poll-\(poll.id)", content: content, trigger: nil))
        return (title, body)
    }

    // MARK: Reminders

    private var reminded = Set<String>()

    /// Before tip-off, for followed teams: "Kentucky kicks off in 30 min". Once per game.
    /// Returns the ids it reminded about (for testing).
    @discardableResult
    func remind(_ games: [Game], followed: Set<String>, now: Date = Date()) -> [String] {
        let mins = Prefs.reminderMinutes
        guard mins > 0 else { return [] }
        var out: [String] = []
        for g in games where g.state == .upcoming {
            guard followed.contains(g.away.teamID) || followed.contains(g.home.teamID) else { continue }
            let until = g.start.timeIntervalSince(now)
            guard until > 0, until <= Double(mins) * 60, reminded.insert(g.id).inserted else { continue }
            out.append(g.id)
            let mine = followed.contains(g.away.teamID) ? g.away : g.home
            func label(_ s: Side) -> String { (s.rank.map { "#\($0) " } ?? s.seed.map { "(\($0)) " } ?? "") + s.name }
            let content = UNMutableNotificationContent()
            let left = max(1, Int((until / 60).rounded()))
            content.title = "🏈 \(mine.name) kicks off in \(left) min"
            content.body = "\(label(g.away)) @ \(label(g.home))" + (g.network.map { " · \($0)" } ?? "")
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "\(g.id)-reminder", content: content, trigger: nil))
        }
        return out
    }

    // MARK: Permission

    func start() { UNUserNotificationCenter.current().delegate = self }

    /// Ask macOS for permission. If it was turned off earlier, offer to open System Settings.
    static func requestPermission(completion: @escaping @MainActor (Bool) -> Void) {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .denied {
                let a = NSAlert()
                a.messageText = "Notifications are turned off for Gridiron Ticker Pro"
                a.informativeText = "To get alerts about your team's games, allow notifications for Gridiron Ticker Pro in System Settings › Notifications."
                a.addButton(withTitle: "Open System Settings")
                a.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                if a.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
                completion(false)
                return
            }
            let ok = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            completion(ok)
        }
    }

    /// Show banners even though the app counts as "active" while its menu is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
