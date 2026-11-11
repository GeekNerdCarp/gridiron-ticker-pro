import AppKit
@preconcurrency import UserNotifications

// MARK: - Model

struct FantasyPlayer: Codable, Equatable {
    let id: String
    let name: String
    let pos: String        // QB, RB, WR, TE
    let teamID: String
    let teamAbbr: String
    var short: String {    // "Josh Allen" -> "J. Allen"
        let parts = name.split(separator: " ")
        guard parts.count >= 2, let f = parts.first?.first else { return name }
        return "\(f). " + parts.dropFirst().joined(separator: " ")
    }
}

/// One player's stats in one game, scored with ESPN's standard fantasy rules (no kickers or defenses).
struct FantasyStats: Equatable {
    var passYds = 0.0, passTD = 0, passAtt = "", ints = 0
    var rushYds = 0.0, rushTD = 0, rushCar = 0
    var recYds = 0.0, recTD = 0, rec = 0
    var retTD = 0
    var fumLost = 0

    var touchdowns: Int { passTD + rushTD + recTD + retTD }
    /// ESPN standard: 1 pt per 25 passing yds, 4 per passing TD, -2 per INT or lost fumble,
    /// 1 pt per 10 rushing or receiving yds, 6 per TD. (Two-point conversions aren't in the box score feed.)
    var points: Double {
        let p = passYds * 0.04 + Double(passTD) * 4 - Double(ints) * 2
            + (rushYds + recYds) * 0.1 + Double(rushTD + recTD + retTD) * 6 - Double(fumLost) * 2
        return (p * 100).rounded() / 100
    }
    /// "24/31, 250 yds, 2 TD, 1 INT" style summary of what the player actually did.
    var line: String {
        var bits: [String] = []
        if !passAtt.isEmpty { bits.append("\(passAtt) \(Int(passYds)) pass yds") }
        if passTD > 0 { bits.append("\(passTD) pass TD") }
        if ints > 0 { bits.append("\(ints) INT") }
        if rushCar > 0 { bits.append("\(rushCar) car \(Int(rushYds)) yds") }
        if rushTD > 0 { bits.append("\(rushTD) rush TD") }
        if rec > 0 { bits.append("\(rec) rec \(Int(recYds)) yds") }
        if recTD > 0 { bits.append("\(recTD) rec TD") }
        if retTD > 0 { bits.append("\(retTD) ret TD") }
        if fumLost > 0 { bits.append("\(fumLost) fumble lost") }
        return bits.joined(separator: ", ")
    }
}

func fantasyFormat(_ p: Double) -> String { String(format: "%.1f", p) }

struct FantasyWeekRecord: Codable {
    var key: String          // "2-10"
    var label: String        // "Week 10"
    var total: Double
    var opponent: Double?
    var players: [String]    // "J. Allen 18.4"
    var complete: Bool
    var date: Date
}

enum FantasyPrefs {
    private static let d = UserDefaults.standard
    static func load(_ key: String) -> [FantasyPlayer] {
        guard let data = d.data(forKey: key), let list = try? JSONDecoder().decode([FantasyPlayer].self, from: data) else { return [] }
        return list
    }
    static func save(_ list: [FantasyPlayer], _ key: String) { d.set(try? JSONEncoder().encode(list), forKey: key) }
    /// 0 off, 1 mixed in at the front of the ticker, 2 only my roster.
    static var display: Int { get { d.integer(forKey: "fantasyDisplay") } set { d.set(newValue, forKey: "fantasyDisplay") } }
    static var menuBar: Bool { get { d.bool(forKey: "fantasyMenuBar") } set { d.set(newValue, forKey: "fantasyMenuBar") } }
    static var alerts: Bool { get { d.bool(forKey: "fantasyAlerts") } set { d.set(newValue, forKey: "fantasyAlerts") } }
    /// Alert when a player reaches this many points; 0 = off.
    static var threshold: Int { get { d.integer(forKey: "fantasyThreshold") } set { d.set(newValue, forKey: "fantasyThreshold") } }
    static var history: [FantasyWeekRecord] {
        get {
            guard let data = d.data(forKey: "fantasyHistory"),
                  let h = try? JSONDecoder().decode([FantasyWeekRecord].self, from: data) else { return [] }
            return h
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "fantasyHistory") }
    }
}

// MARK: - Player pool (search)

enum FantasyPool {
    private struct RosterResponse: Decodable {
        let athletes: [Group]?
        let team: Team?
        struct Team: Decodable { let id: String; let abbreviation: String? }
        struct Group: Decodable { let items: [Lossy<Ath>]? }
        struct Ath: Decodable {
            let id: String
            let displayName: String
            let position: Pos?
            struct Pos: Decodable { let abbreviation: String? }
        }
    }

    private static let keep: Set<String> = ["QB", "RB", "WR", "TE"]
    private static var cacheFile: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("app.gridirontickerpro.mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("fantasy-pool.json")
    }

    /// Every QB, RB, WR and TE on an NFL roster. Cached for a day, since 32 requests is a lot to repeat.
    static func load(teamIDs: [String]) async -> [FantasyPlayer] {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
           let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 24 * 3600,
           let data = try? Data(contentsOf: cacheFile), let list = try? JSONDecoder().decode([FantasyPlayer].self, from: data),
           !list.isEmpty { return list }
        let all = await withTaskGroup(of: [FantasyPlayer].self) { tasks in
            for id in teamIDs {
                tasks.addTask {
                    guard let r = try? await ESPN.get(RosterResponse.self, "\(ESPN.base)/teams/\(id)/roster") else { return [] }
                    let abbr = r.team?.abbreviation ?? ""
                    return (r.athletes ?? []).flatMap { $0.items ?? [] }.compactMap { $0.value }.compactMap { a in
                        guard let pos = a.position?.abbreviation, keep.contains(pos) else { return nil }
                        return FantasyPlayer(id: a.id, name: a.displayName, pos: pos, teamID: id, teamAbbr: abbr)
                    }
                }
            }
            var out: [FantasyPlayer] = []
            for await list in tasks { out += list }
            return out
        }
        let sorted = all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if sorted.count > 200 { try? JSONEncoder().encode(sorted).write(to: cacheFile) }
        return sorted
    }
}

// MARK: - Stats feed

extension ESPN {
    /// Per-player fantasy stats and injury statuses for one game (the same ~400 KB summary the box score uses).
    static func fetchFantasyGame(gameID: String) async throws -> (stats: [String: FantasyStats], injuries: [String: String]) {
        let r = try await get(SummaryResponse.self, "\(base)/summary?event=\(gameID)")
        var stats: [String: FantasyStats] = [:]
        func n(_ s: String?) -> Double { Double((s ?? "").replacingOccurrences(of: ",", with: "")) ?? 0 }
        for pb in r.boxscore?.players ?? [] {
            for g in pb.statistics ?? [] {
                guard let name = g.name, let labels = g.labels else { continue }
                for a in g.athletes ?? [] {
                    guard let id = a.athlete.id, let st = a.stats else { continue }
                    func v(_ label: String) -> String? {
                        guard let i = labels.firstIndex(of: label), st.indices.contains(i) else { return nil }
                        return st[i]
                    }
                    var s = stats[id] ?? FantasyStats()
                    switch name {
                    case "passing": s.passYds = n(v("YDS")); s.passTD = Int(n(v("TD"))); s.ints = Int(n(v("INT"))); s.passAtt = v("C/ATT") ?? ""
                    case "rushing": s.rushYds = n(v("YDS")); s.rushTD = Int(n(v("TD"))); s.rushCar = Int(n(v("CAR")))
                    case "receiving": s.recYds = n(v("YDS")); s.recTD = Int(n(v("TD"))); s.rec = Int(n(v("REC")))
                    case "fumbles": s.fumLost = Int(n(v("LOST")))
                    case "kickReturns", "puntReturns": s.retTD += Int(n(v("TD")))
                    default: break
                    }
                    stats[id] = s
                }
            }
        }
        var injuries: [String: String] = [:]
        for t in r.injuries ?? [] {
            for i in t.value?.injuries ?? [] {
                if let id = i.value?.athlete?.id, let st = i.value?.status { injuries[id] = st }
            }
        }
        return (stats, injuries)
    }
}

// MARK: - Store

/// Holds the roster, keeps its stats fresh, and tells the ticker, menu bar and notifications what changed.
@MainActor
final class FantasyStore {
    static let shared = FantasyStore()

    var roster: [FantasyPlayer] = FantasyPrefs.load("fantasyRoster")
    var opponent: [FantasyPlayer] = FantasyPrefs.load("fantasyOpponent")
    private(set) var stats: [String: FantasyStats] = [:]
    private(set) var injuries: [String: String] = [:]
    private var games: [Game] = []        // this week, then next week
    private var currentGames: [Game] = [] // this week only
    private var finalDone = Set<String>()          // final games already fetched
    private var lastFetch: [String: Date] = [:]
    private var seeded = Set<String>()             // games we've fetched once (no alerts for what was already there)
    private var thresholdHit = Set<String>()       // "gameID-playerID"
    private var injuryTold: [String: String] = [:]
    var weekKey = "", weekLabel = ""
    var onChange: (() -> Void)?

    func setRoster(_ list: [FantasyPlayer]) { roster = list; FantasyPrefs.save(list, "fantasyRoster"); resetFetchState() }
    func setOpponent(_ list: [FantasyPlayer]) { opponent = list; FantasyPrefs.save(list, "fantasyOpponent"); resetFetchState() }
    /// A changed roster needs its games looked at again right away.
    private func resetFetchState() { finalDone.removeAll(); lastFetch.removeAll() }

    var isEmpty: Bool { roster.isEmpty }

    func game(for p: FantasyPlayer) -> Game? {
        games.first { $0.involves(p.teamID) }
    }
    func points(_ p: FantasyPlayer) -> Double { stats[p.id]?.points ?? 0 }
    var total: Double { roster.reduce(0) { $0 + points($1) } }
    var opponentTotal: Double { opponent.reduce(0) { $0 + points($1) } }
    func isRostered(_ playerID: String) -> Bool { roster.contains { $0.id == playerID } }

    /// "J. Allen 18.4 pts" lines for your players in a game, for the box-score popup.
    func lines(in g: Game) -> [String] {
        roster.filter { $0.teamID == g.away.teamID || $0.teamID == g.home.teamID }.map {
            "★ \($0.short) (\($0.pos))  \(fantasyFormat(points($0))) pts" + (stats[$0.id].map { $0.line.isEmpty ? "" : " · " + $0.line } ?? "")
        }
    }

    // MARK: Refresh

    /// Fetch stats for every game your players (and opponent's) are in. Live games every 30 seconds,
    /// finished games once, upcoming games every 30 minutes (for injury statuses).
    func refresh(games current: [Game], next: [Game], week: ESPN.Week?) async {
        let all = current + next
        games = all
        currentGames = current
        if let w = week { weekKey = "\(w.type)-\(w.number)"; weekLabel = w.label }
        let teamIDs = Set((roster + opponent).map { $0.teamID })
        guard !teamIDs.isEmpty else { return }
        let now = Date()
        var todo: [Game] = []
        for g in all where teamIDs.contains(g.away.teamID) || teamIDs.contains(g.home.teamID) {
            switch g.state {
            case .live: if now.timeIntervalSince(lastFetch[g.id] ?? .distantPast) >= 30 { todo.append(g) }
            case .final: if !finalDone.contains(g.id) { todo.append(g) }
            case .upcoming: if now.timeIntervalSince(lastFetch[g.id] ?? .distantPast) >= 1800 { todo.append(g) }
            }
        }
        guard !todo.isEmpty else { return }
        let results = await withTaskGroup(of: (Game, (stats: [String: FantasyStats], injuries: [String: String])?).self) { tasks in
            for g in todo { tasks.addTask { (g, try? await ESPN.fetchFantasyGame(gameID: g.id)) } }
            var out: [(Game, (stats: [String: FantasyStats], injuries: [String: String])?)] = []
            for await r in tasks { out.append(r) }
            return out
        }
        for (g, res) in results {
            guard let res else { continue }
            lastFetch[g.id] = now
            if g.state == .final { finalDone.insert(g.id) }
            let first = seeded.insert(g.id).inserted
            for (id, new) in res.stats where (roster + opponent).contains(where: { $0.id == id }) {
                if !first, g.state == .live, FantasyPrefs.alerts, let p = roster.first(where: { $0.id == id }) { alert(p, old: stats[id] ?? FantasyStats(), new: new, game: g) }
                stats[id] = new
            }
            for (id, st) in res.injuries where (roster + opponent).contains(where: { $0.id == id }) {
                if let p = roster.first(where: { $0.id == id }), FantasyPrefs.alerts, g.state == .upcoming, !first,
                   injuryTold[id] != st, ["Out", "Doubtful", "Inactive"].contains(st) {
                    post("\(p.short) is \(st.uppercased())", "\(p.name) (\(p.teamAbbr)) · \(g.away.abbr ?? g.away.name) @ \(g.home.abbr ?? g.home.name)", id: "inj-\(id)-\(st)")
                }
                injuries[id] = st
                injuryTold[id] = st
            }
        }
        recordHistory()
        onChange?()
    }

    // MARK: Alerts

    private func alert(_ p: FantasyPlayer, old: FantasyStats, new: FantasyStats, game g: Game) {
        if new.touchdowns > old.touchdowns {
            let kind = new.passTD > old.passTD ? "passing TD" : (new.rushTD > old.rushTD ? "rushing TD" : (new.recTD > old.recTD ? "receiving TD" : "return TD"))
            post("\(p.short) \(kind)", "Now \(fantasyFormat(new.points)) fantasy pts · \(new.line)", id: "fan-\(g.id)-\(p.id)-td\(new.touchdowns)")
        }
        let t = FantasyPrefs.threshold
        if t > 0, new.points >= Double(t), old.points < Double(t), thresholdHit.insert("\(g.id)-\(p.id)").inserted {
            post("\(p.short) hit \(t) points", "\(fantasyFormat(new.points)) pts · \(new.line)", id: "fan-\(g.id)-\(p.id)-t\(t)")
        }
    }

    private func post(_ title: String, _ body: String, id: String) {
        let c = UNMutableNotificationContent()
        c.title = "🏈 " + title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    // MARK: History

    /// Keep this week's totals (updated as the games go) so past weeks stay available.
    private func recordHistory() {
        guard !weekKey.isEmpty, !roster.isEmpty, !stats.isEmpty else { return }
        let teamIDs = Set(roster.map { $0.teamID })
        let mine = currentGames.filter { teamIDs.contains($0.away.teamID) || teamIDs.contains($0.home.teamID) }
        guard mine.contains(where: { $0.state != .upcoming }) else { return }
        let complete = mine.allSatisfy { $0.state == .final }
        let rec = FantasyWeekRecord(key: weekKey, label: weekLabel, total: total,
                                    opponent: opponent.isEmpty ? nil : opponentTotal,
                                    players: roster.map { "\($0.short) \(fantasyFormat(points($0)))" },
                                    complete: complete, date: Date())
        var h = FantasyPrefs.history
        if let i = h.firstIndex(where: { $0.key == weekKey }) { h[i] = rec } else { h.append(rec) }
        FantasyPrefs.history = h
    }

    // MARK: Ticker text

    private func state(_ p: FantasyPlayer) -> (Game?, GameState?) {
        let g = game(for: p)
        return (g, g?.state)
    }

    /// The injury tag worth showing: "OUT", "DOUBTFUL" or "QUESTIONABLE" (shortened to Q).
    private func tag(_ p: FantasyPlayer) -> (String, NSColor)? {
        switch injuries[p.id] ?? "" {
        case "Out", "Inactive": return ("OUT", Palette.alert)
        case "Doubtful": return ("DOUBTFUL", Palette.alert)
        case "Questionable": return ("Q", Palette.marquee)
        default: return nil
        }
    }

    /// Ticker entries: first the lineup total (and matchup), then one per player, scoring players first.
    func segments(font: NSFont) -> (segments: [NSAttributedString], keys: [String]) {
        guard !roster.isEmpty else { return ([], []) }
        var segs: [NSAttributedString] = [], keys: [String] = []
        func add(_ s: String, _ c: NSColor, to out: NSMutableAttributedString) {
            out.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c]))
        }
        func badge(_ s: String, _ bg: NSColor, to out: NSMutableAttributedString) {
            out.append(NSAttributedString(string: " \(s) ", attributes: [.font: font, .foregroundColor: NSColor.black, .backgroundColor: bg]))
            add("  ", Palette.dim, to: out)
        }
        let sep = "      ◆      "

        let head = NSMutableAttributedString()
        add("MY TEAM ", Palette.favorite, to: head)
        add(fantasyFormat(total), Palette.liveScore, to: head)
        if !opponent.isEmpty {
            let d = total - opponentTotal
            add("  –  ", Palette.dim, to: head)
            add("OPP ", Palette.name, to: head)
            add(fantasyFormat(opponentTotal), Palette.score, to: head)
            add(d > 0 ? "   WINNING BY \(fantasyFormat(d))" : (d < 0 ? "   LOSING BY \(fantasyFormat(-d))" : "   TIED"), d >= 0 ? Palette.liveScore : Palette.live, to: head)
        }
        add(sep, Palette.dim, to: head)
        segs.append(head); keys.append("fan-total")

        func order(_ p: FantasyPlayer) -> Int {
            switch state(p).1 { case .live?: return 0; case .final?: return 1; case .upcoming?: return 2; default: return 3 }
        }
        let sorted = roster.enumerated().sorted {
            let (a, b) = ($0.element, $1.element)
            if order(a) != order(b) { return order(a) < order(b) }
            if order(a) <= 1, points(a) != points(b) { return points(a) > points(b) }
            return $0.offset < $1.offset
        }.map { $0.element }

        for p in sorted {
            let out = NSMutableAttributedString()
            let (g, st) = state(p)
            add("★ ", Palette.favorite, to: out)
            if let t = tag(p) { badge(t.0, t.1, to: out) }
            add(p.short.uppercased(), Palette.name, to: out)
            add(" \(p.pos) · \(p.teamAbbr)", Palette.dim, to: out)
            switch st {
            case .live?, .final?:
                add("  \(fantasyFormat(points(p))) PTS", st == .live ? Palette.liveScore : Palette.score, to: out)
                if let s = stats[p.id], !s.line.isEmpty { add("  ·  \(s.line)", Palette.network, to: out) }
                if let g { add("   " + (st == .live ? g.detail : "FINAL").uppercased(), st == .live ? Palette.live : Palette.final, to: out) }
            case .upcoming?:
                if let g {
                    let opp = g.away.teamID == p.teamID ? "@ \(g.home.abbr ?? g.home.name)" : "vs \(g.away.abbr ?? g.away.name)"
                    add("  \(opp)   \(g.detail.uppercased())", Palette.upcoming, to: out)
                    if let n = g.network { add(" · \(n.uppercased())", Palette.network, to: out) }
                    if let o = g.odds { add(" · \(o)", Palette.network, to: out) }
                }
            default:
                add(ESPN.byeTeamIDs.contains(p.teamID) ? "  BYE WEEK" : "  NO GAME", Palette.dim, to: out)
            }
            add(sep, Palette.dim, to: out)
            segs.append(out); keys.append("fan-\(p.id)")
        }
        return (segs, keys)
    }

    /// Menu-bar text: "FP 84.2", or "FP 84.2–71.9" with an opponent.
    var menuBarText: String {
        guard !roster.isEmpty else { return "" }
        return opponent.isEmpty ? "FP \(fantasyFormat(total))" : "FP \(fantasyFormat(total))–\(fantasyFormat(opponentTotal))"
    }
}
