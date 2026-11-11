import Foundation

// MARK: - ESPN JSON (only the fields we use; everything else ignored)

struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct StatusJSON: Decodable {
    let type: Ty
    let clock: Double?     // seconds left in the period
    let period: Int?       // 1, 2, then 3+ for overtimes
    struct Ty: Decodable {
        let name: String?          // e.g. "STATUS_HALFTIME"
        let state: String          // "pre", "in", "post"
        let shortDetail: String?   // e.g. "13:02 - 1st", "Halftime", "Final"
    }
}

struct CompetitorJSON: Decodable {
    let homeAway: String
    let score: String?
    let team: Tm
    let record: String?   // overall, e.g. "2-0"
    struct Tm: Decodable {
        let id: String
        let displayName: String
        let shortDisplayName: String?
        let abbreviation: String?
    }

    /// Scoreboard: records[{type:"total", summary}]. Team schedule: record[{type:"total", displayValue}].
    private struct Rec: Decodable { let type: String?; let summary: String?; let displayValue: String? }
    enum CodingKeys: String, CodingKey { case homeAway, score, team, records, record }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        homeAway = try c.decode(String.self, forKey: .homeAway)
        team = try c.decode(Tm.self, forKey: .team)
        let recs = (try? c.decode([Lossy<Rec>].self, forKey: .records))
            ?? (try? c.decode([Lossy<Rec>].self, forKey: .record)) ?? []
        let total = recs.compactMap { $0.value }.first { $0.type == "total" }
        record = total?.summary ?? total?.displayValue
        // Scoreboard sends score as "71"; team schedule sends {"displayValue":"71"}.
        if let s = try? c.decode(String.self, forKey: .score) {
            score = s
        } else if let o = try? c.decode([String: Lossy<String>].self, forKey: .score) {
            score = o["displayValue"]?.value
        } else {
            score = nil
        }
    }
}

/// Scoreboard: {"market":"national","names":["ESPN2"]}.
/// Team schedule: {"type":{"shortName":"TV"},"market":{"type":"National"},"media":{"shortName":"ESPN"}}.
struct BroadcastJSON: Decodable {
    let name: String?
    let national: Bool
    let radio: Bool

    private struct Named: Decodable { let shortName: String? }
    private struct Market: Decodable { let type: String? }
    enum CodingKeys: String, CodingKey { case names, market, media, type }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let names = (try? c.decode([String].self, forKey: .names)) ?? []
        name = names.first ?? (try? c.decode(Named.self, forKey: .media))?.shortName
        let market = (try? c.decode(String.self, forKey: .market))
            ?? (try? c.decode(Market.self, forKey: .market))?.type ?? ""
        national = market.lowercased() == "national"
        radio = (try? c.decode(Named.self, forKey: .type))?.shortName == "Radio"
    }
}

/// Competition odds: {"details":"HOU -10","overUnder":44.5,"spread":-10.0,...}. Absent for many games.
struct OddsJSON: Decodable {
    let details: String?
    let overUnder: Double?
}

struct Board: Decodable {
    let events: [Lossy<Ev>]
    let week: WeekInfo?
    let leagues: [League]?

    struct WeekInfo: Decodable {
        let number: Int?
        let teamsOnBye: [Lossy<ByeTeam>]?
    }
    struct ByeTeam: Decodable { let id: String }
    struct League: Decodable { let calendar: [Lossy<CalType>]? }
    /// One season phase: "1" preseason, "2" regular season, "3" postseason, each with its weeks.
    struct CalType: Decodable {
        let value: String
        let entries: [Lossy<CalEntry>]?
    }
    struct CalEntry: Decodable {
        let label: String?
        let value: String
        let startDate: String
        let endDate: String
    }
}

struct Ev: Decodable {
    let id: String
    let date: String
    let status: StatusJSON?          // scoreboard puts status here…
    let competitions: [Comp]
    let season: Season?              // type 2 regular season, 3 postseason
    struct Season: Decodable { let type: Int? }
    struct Comp: Decodable {
        let status: StatusJSON?      // …team schedule puts it here
        let competitors: [CompetitorJSON]
        let broadcasts: [Lossy<BroadcastJSON>]?
        let notes: [Lossy<Note>]?
        let odds: [Lossy<OddsJSON>]?
        struct Note: Decodable { let headline: String? }
    }
}

struct TeamsResponse: Decodable {
    let sports: [S]
    struct S: Decodable { let leagues: [L] }
    struct L: Decodable { let teams: [W] }
    struct W: Decodable { let team: T }
    struct T: Decodable { let id: String; let displayName: String; let color: String?; let alternateColor: String? }
}

// MARK: - App model

enum GameState { case live, upcoming, final }

struct Side {
    let teamID: String
    let name: String
    let score: String?
    var record: String? = nil
    var abbr: String? = nil   // e.g. "UK"
}

struct Game {
    let id: String
    let state: GameState
    let away: Side
    let home: Side
    let detail: String
    let start: Date
    let network: String?   // e.g. "ESPN2", nil if ESPN doesn't list one
    var round: String? = nil   // postseason round, e.g. "WILD CARD" (set in a later phase)
    var odds: String? = nil        // ESPN's line, e.g. "HOU -10"
    var overUnder: Double? = nil
    var period = 0
    var clock: Double = 0
    var isHalftime = false

    func involves(_ teamID: String) -> Bool { away.teamID == teamID || home.teamID == teamID }

    /// Points between the teams, if both scores are known.
    var margin: Int? {
        guard let a = Int(away.score ?? ""), let h = Int(home.score ?? "") else { return nil }
        return abs(a - h)
    }
    /// Spoiler-free mode: should this game's score stay hidden? Games that haven't started have none.
    var scoresHidden: Bool {
        guard state != .upcoming else { return false }
        switch Prefs.spoilerMode {
        case 2: return true
        case 1: return Prefs.followedIDs.contains { involves($0) }
        default: return false
        }
    }

    /// Win share from a record like "7-2" or "5-2-1" (a tie counts half), with games played.
    private static func winShare(_ rec: String?) -> (pct: Double, games: Int)? {
        let p = (rec ?? "").split(separator: "-").compactMap { Int($0) }
        guard p.count >= 2 else { return nil }
        let games = p.reduce(0, +)
        guard games > 0 else { return nil }
        return ((Double(p[0]) + Double(p.count > 2 ? p[2] : 0) / 2) / Double(games), games)
    }
    /// A matchup worth circling: both teams at .700 or better after six or more games. Finished games don't count.
    var isMarquee: Bool {
        guard state != .final,
              let a = Game.winShare(away.record), let h = Game.winShare(home.record) else { return false }
        return a.games >= 6 && h.games >= 6 && a.pct >= 0.7 && h.pct >= 0.7
    }
    /// ESPN's favorite and spread from the line, e.g. "HOU -10" -> ("HOU", 10). Nil for "EVEN" or no line.
    var favorite: (abbr: String, spread: Double)? {
        let parts = (odds ?? "").split(separator: " ")
        guard parts.count == 2, let s = Double(parts[1]), s < 0 else { return nil }
        return (String(parts[0]), -s)
    }
    /// Live, fourth quarter or overtime, 4:00 or less left, within one score (8 points).
    var isCloseLate: Bool {
        guard state == .live, period >= 4, clock <= 240, let m = margin else { return false }
        return m <= 8   // one possession
    }
    /// Live in the second half or overtime, with a team favored by a touchdown or more trailing.
    var isUpsetBrewing: Bool {
        guard state == .live, period >= 3, !isHalftime, let fav = favorite, fav.spread >= 6.5,
              let a = Int(away.score ?? ""), let h = Int(home.score ?? "") else { return false }
        if fav.abbr == away.abbr { return h > a }
        if fav.abbr == home.abbr { return a > h }
        return false
    }
}

struct TeamInfo {
    let id: String
    let name: String
    var color: String? = nil      // hex like "0033a0"
    var altColor: String? = nil
}

// MARK: - Networking

enum ESPN {
    static let base = "https://site.api.espn.com/apis/site/v2/sports/football/nfl"

    private static let startParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return f
    }()

    private static let timeOnly: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    private static let dayAndTime: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE M/d h:mm a"; return f
    }()

    private static let dateParam: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    /// Why a request didn't go out or didn't succeed.
    enum RequestError: LocalizedError {
        case slowDown(seconds: Int)      // ESPN pushed back; we're waiting before asking again
        case badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .slowDown(let s): return "ESPN asked us to slow down; trying again in \(s) s"
            case .badStatus(let c): return "ESPN answered with status \(c)"
            }
        }
    }

    /// Keeps us a polite client: at most a few requests at once, and when ESPN answers 429 or a 5xx error
    /// we stop asking for a while (its Retry-After if it gives one, else 5 s doubling up to 5 minutes).
    /// During that pause requests fail at once instead of piling on, and the ticker keeps the last good data.
    private actor RequestGate {
        private let limit = 4
        private var inFlight = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var cooldownUntil = Date.distantPast
        private var failures = 0

        func acquire() async throws {
            let wait = cooldownUntil.timeIntervalSinceNow
            if wait > 0 { throw RequestError.slowDown(seconds: Int(wait.rounded(.up))) }
            if inFlight < limit { inFlight += 1; return }
            await withCheckedContinuation { waiters.append($0) }   // a finishing request hands us its slot
        }
        func release() {
            if waiters.isEmpty { inFlight -= 1 } else { waiters.removeFirst().resume() }
        }
        func succeeded() { failures = 0 }
        func pushedBack(retryAfter: TimeInterval?) {
            failures += 1
            let delay = min(300, max(retryAfter ?? 0, 5 * pow(2, Double(min(failures, 7) - 1))))
            cooldownUntil = max(cooldownUntil, Date().addingTimeInterval(delay))
        }
        var remaining: Int { max(0, Int(cooldownUntil.timeIntervalSinceNow.rounded(.up))) }
    }
    private static let gate = RequestGate()

    /// Seconds left in a "slow down" pause, for the menu.
    static func cooldownRemaining() async -> Int { await gate.remaining }

    static func get<T: Decodable>(_ type: T.Type, _ url: String) async throws -> T {
        try await gate.acquire()
        let data: Data
        do {
            var req = URLRequest(url: URL(string: url)!)
            req.timeoutInterval = 20
            let (d, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                if http.statusCode == 429 || http.statusCode >= 500 {
                    await gate.pushedBack(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) })
                }
                await gate.release()
                throw RequestError.badStatus(http.statusCode)
            }
            data = d
        } catch let e as RequestError {
            throw e
        } catch {
            await gate.release()
            throw error
        }
        await gate.succeeded()
        await gate.release()
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// One NFL week of the schedule: season type 1 preseason, 2 regular season, 3 postseason.
    struct Week: Equatable {
        let type: Int
        let number: Int
        let start: Date
        let end: Date
        var label = ""   // "Week 10", "Wild Card", …
    }

    /// NFL weeks run Thursday to Wednesday, so a whole week (including Monday night) is one scoreboard.
    /// ESPN's calendar lists every week with its dates; we pick by date and always pass an explicit week.
    private static let weekLock = NSLock()
    nonisolated(unsafe) private static var weekCache: (fetched: Date, weeks: [Week])?
    nonisolated(unsafe) private static var byes: [String] = []

    /// Team ids on a bye in the most recently fetched week.
    static var byeTeamIDs: [String] {
        weekLock.withLock { byes }
    }

    static func calendar() async throws -> [Week] {
        if let c = weekLock.withLock({ weekCache }), Date().timeIntervalSince(c.fetched) < 6 * 3600 { return c.weeks }
        let board = try await get(Board.self, "\(base)/scoreboard")
        var weeks: [Week] = []
        for t in (board.leagues?.first?.calendar ?? []).compactMap({ $0.value }) {
            guard let type = Int(t.value) else { continue }
            for e in (t.entries ?? []).compactMap({ $0.value }) {
                if let n = Int(e.value), let s = startParser.date(from: e.startDate), let en = startParser.date(from: e.endDate) {
                    weeks.append(Week(type: type, number: n, start: s, end: en, label: e.label ?? "Week \(n)"))
                }
            }
        }
        weeks.sort { $0.start < $1.start }
        guard !weeks.isEmpty else { throw URLError(.cannotParseResponse) }
        weekLock.withLock { weekCache = (Date(), weeks) }
        return weeks
    }

    /// The week containing `day`; between seasons, the most recent one (or the first, before the preseason).
    static func week(containing day: Date, in weeks: [Week]) -> Int {
        weeks.lastIndex { $0.start <= day } ?? 0
    }

    static func fetchWeek(_ w: Week) async throws -> [Game] {
        let board = try await get(Board.self, "\(base)/scoreboard?week=\(w.number)&seasontype=\(w.type)&limit=100")
        if w.start <= Date() && Date() < w.end {
            let ids = (board.week?.teamsOnBye ?? []).compactMap { $0.value?.id }
            weekLock.withLock { byes = ids }
        }
        return board.events.compactMap { $0.value }.compactMap(makeGame)
    }

    /// The week the calendar says it is now.
    static func currentWeek() async -> Week? {
        guard let weeks = try? await calendar() else { return nil }
        return weeks[week(containing: Date(), in: weeks)]
    }

    /// The week that contains `day`.
    static func fetchBoard(on day: Date) async throws -> [Game] {
        let weeks = try await calendar()
        return try await fetchWeek(weeks[week(containing: day, in: weeks)])
    }

    /// What the ticker treats as "today": this NFL week's games, finished ones included.
    static func fetchToday() async throws -> [Game] {
        try await fetchBoard(on: Date())
    }

    /// Next week's games, as element 0. A failed fetch comes back empty.
    static func fetchLookahead() async -> [[Game]] {
        guard let weeks = try? await calendar() else { return [[]] }
        let i = week(containing: Date(), in: weeks)
        guard i + 1 < weeks.count else { return [[]] }
        return [(try? await fetchWeek(weeks[i + 1])) ?? []]
    }

    /// A team's next game that hasn't started, from its full-season schedule.
    static func fetchNextGame(teamID: String) async throws -> Game? {
        let board = try await get(Board.self, "\(base)/teams/\(teamID)/schedule")
        let now = Date()
        return board.events.compactMap { $0.value }.compactMap(makeGame)
            .filter { $0.state == .upcoming && $0.start > now }
            .min { $0.start < $1.start }
    }

    static func fetchTeams() async throws -> [TeamInfo] {
        let r = try await get(TeamsResponse.self, "\(base)/teams?limit=100")
        return (r.sports.first?.leagues.first?.teams ?? [])
            .map { TeamInfo(id: $0.team.id, name: $0.team.displayName, color: $0.team.color, altColor: $0.team.alternateColor) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// "Wild Card Playoffs" -> "WILD CARD", "NFC Championship" -> "NFC CHAMPIONSHIP", "Super Bowl LXI" -> "SUPER BOWL LXI".
    static func roundLabel(_ headline: String) -> String? {
        var h = headline.trimmingCharacters(in: .whitespaces)
        for tail in [" Playoffs", " Round"] where h.hasSuffix(tail) { h = String(h.dropLast(tail.count)) }
        return h.isEmpty ? nil : h.uppercased()
    }

    private static func makeGame(_ e: Ev) -> Game? {
        guard let comp = e.competitions.first,
              let status = e.status ?? comp.status,
              let away = comp.competitors.first(where: { $0.homeAway == "away" }),
              let home = comp.competitors.first(where: { $0.homeAway == "home" }) else { return nil }

        // Playoff games whose teams aren't decided yet come as "TBD at TBD" with negative ids; skip them.
        if away.team.id.hasPrefix("-") && home.team.id.hasPrefix("-") { return nil }
        let headline = comp.notes?.compactMap { $0.value?.headline }.first ?? ""
        func side(_ c: CompetitorJSON) -> Side {
            Side(teamID: c.team.id,
                 name: c.team.shortDisplayName ?? c.team.displayName,
                 score: c.score,
                 record: c.record,
                 abbr: c.team.abbreviation)
        }
        let start = startParser.date(from: e.date) ?? Date()
        let state: GameState
        var detail = status.type.shortDetail ?? ""
        switch status.type.state {
        case "in":
            state = .live
        case "post":
            state = .final
            if detail.isEmpty { detail = "Final" }
        default:
            state = .upcoming
            detail = Calendar.current.isDateInToday(start)
                ? timeOnly.string(from: start)
                : dayAndTime.string(from: start)
        }
        // Prefer a national TV listing over local or radio ones.
        let casts = (comp.broadcasts ?? []).compactMap { $0.value }.filter { !$0.radio && $0.name?.isEmpty == false }
        let network = (casts.first { $0.national } ?? casts.first)?.name
        var game = Game(id: e.id, state: state, away: side(away), home: side(home), detail: detail,
                        start: start, network: network)
        if state != .final, let o = comp.odds?.compactMap({ $0.value }).first {
            game.odds = o.details
            game.overUnder = o.overUnder
        }
        if e.season?.type == 3 { game.round = roundLabel(headline) }
        game.period = status.period ?? 0
        game.clock = status.clock ?? 0
        game.isHalftime = status.type.name == "STATUS_HALFTIME"
        return game
    }
}

// MARK: - Box score

struct SummaryResponse: Decodable {
    let boxscore: Box?
    let drives: Drives?
    let injuries: [Lossy<InjuryTeam>]?
    let scoringPlays: [Lossy<ScoringPlay>]?
    let header: Header?
    struct ScoringPlay: Decodable {
        let text: String?
        let type: TypeText?
        let team: TeamRef?
        let awayScore: Int?
        let homeScore: Int?
    }
    struct TypeText: Decodable { let text: String? }
    struct Header: Decodable {
        let competitions: [Comp]?
        struct Comp: Decodable { let competitors: [Competitor]? }
        struct Competitor: Decodable { let homeAway: String?; let team: TeamRef; let score: String? }
    }
    struct InjuryTeam: Decodable { let injuries: [Lossy<Injury>]? }
    struct Injury: Decodable { let status: String?; let athlete: Person? }
    struct Box: Decodable { let teams: [TeamBox]?; let players: [PlayersBox]? }
    struct TeamRef: Decodable { let id: String }
    struct TeamBox: Decodable { let team: TeamRef; let statistics: [Stat]? }
    struct Stat: Decodable { let name: String?; let displayValue: String? }
    struct PlayersBox: Decodable { let team: TeamRef; let statistics: [Group]? }
    struct Group: Decodable { let name: String?; let labels: [String]?; let athletes: [Athlete]? }
    struct Athlete: Decodable { let athlete: Person; let stats: [String]? }
    struct Person: Decodable { let id: String?; let displayName: String? }
    /// Play-by-play comes as drives: finished ones under `previous`, the one in progress under `current`.
    struct Drives: Decodable { let previous: [Lossy<Drive>]?; let current: Drive? }
    struct Drive: Decodable { let team: TeamRef?; let plays: [Lossy<Play>]? }
    struct Play: Decodable {
        let text: String?
        let type: TypeText?
        let period: Num?
        let clock: Clk?
        struct Num: Decodable { let number: Int? }
        struct Clk: Decodable { let displayValue: String? }
    }
}

/// What the click-through popup shows for one game.
struct BoxScore {
    struct Line {
        var stats: [(label: String, value: String)] = []
        var leaders: [String] = []
    }
    var lines: [String: Line] = [:]   // by team id
    var lastPlay: String?
}

extension ESPN {
    /// A game's team stats, top passer/rusher/receiver and latest play. About 400 KB, so only fetched on a click.
    static func fetchBoxScore(gameID: String) async throws -> BoxScore {
        let r = try await get(SummaryResponse.self, "\(base)/summary?event=\(gameID)")
        var box = BoxScore()
        let keep = [("totalYards", "TOTAL"), ("netPassingYards", "PASS"), ("rushingYards", "RUSH"),
                    ("turnovers", "TO"), ("firstDowns", "1ST"), ("thirdDownEff", "3RD"), ("possessionTime", "TOP")]
        for t in r.boxscore?.teams ?? [] {
            var line = BoxScore.Line()
            for (key, label) in keep {
                if let v = t.statistics?.first(where: { $0.name == key })?.displayValue { line.stats.append((label, v)) }
            }
            box.lines[t.team.id] = line
        }
        // Leader lines: (group, label of the number to rank by, the labels to print).
        let groups: [(String, String, [String])] = [("passing", "YDS", ["C/ATT", "YDS", "TD", "INT"]),
                                                    ("rushing", "YDS", ["CAR", "YDS", "TD"]),
                                                    ("receiving", "YDS", ["REC", "YDS", "TD"])]
        let suffix = ["C/ATT": "", "CAR": " car", "REC": " rec", "YDS": " yds", "TD": " TD", "INT": " INT"]
        for pb in r.boxscore?.players ?? [] {
            var leaders: [String] = []
            for (name, rankBy, show) in groups {
                guard let g = pb.statistics?.first(where: { $0.name == name }), let labels = g.labels,
                      let iRank = labels.firstIndex(of: rankBy) else { continue }
                func num(_ a: SummaryResponse.Athlete) -> Int {
                    guard let st = a.stats, st.indices.contains(iRank) else { return 0 }
                    return Int(st[iRank]) ?? 0
                }
                guard let top = (g.athletes ?? []).max(by: { num($0) < num($1) }), num(top) > 0 else { continue }
                let bits = show.compactMap { l -> String? in
                    guard let i = labels.firstIndex(of: l), let st = top.stats, st.indices.contains(i) else { return nil }
                    // Skip zero touchdowns and interceptions to keep the line short.
                    if (l == "TD" || l == "INT"), st[i] == "0" { return nil }
                    return st[i] + (suffix[l] ?? "")
                }
                leaders.append("\(top.athlete.displayName ?? "?")  " + bits.joined(separator: ", "))
            }
            box.lines[pb.team.id, default: BoxScore.Line()].leaders = leaders
        }
        let drives = (r.drives?.previous?.compactMap { $0.value } ?? []) + [r.drives?.current].compactMap { $0 }
        let plays = drives.flatMap { ($0.plays ?? []).compactMap { $0.value } }
        if let p = plays.last(where: { !($0.text ?? "").isEmpty && !($0.text ?? "").uppercased().hasPrefix("END ") }) {
            let n = p.period?.number ?? 0
            let q = n >= 1 && n <= 4 ? ["1st", "2nd", "3rd", "4th"][n - 1] : (n > 4 ? "OT" : "")
            box.lastPlay = [p.clock?.displayValue, q].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") + " · " + (p.text ?? "")
        }
        return box
    }
}
