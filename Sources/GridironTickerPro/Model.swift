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
    let curatedRank: Rk?
    let record: String?   // overall, e.g. "2-0"
    struct Tm: Decodable {
        let id: String
        let displayName: String
        let shortDisplayName: String?
        let abbreviation: String?
    }
    struct Rk: Decodable { let current: Int }

    /// Scoreboard: records[{type:"total", summary}]. Team schedule: record[{type:"total", displayValue}].
    private struct Rec: Decodable { let type: String?; let summary: String?; let displayValue: String? }
    enum CodingKeys: String, CodingKey { case homeAway, score, team, curatedRank, records, record }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        homeAway = try c.decode(String.self, forKey: .homeAway)
        team = try c.decode(Tm.self, forKey: .team)
        curatedRank = try? c.decode(Rk.self, forKey: .curatedRank)
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

struct ConferencesResponse: Decodable {
    let conferences: [C]
    struct C: Decodable { let name: String; let shortName: String?; let groupId: String }
}

struct Conference {
    let id: Int
    let name: String
}

struct RankingsResponse: Decodable {
    let rankings: [Poll]
    struct Poll: Decodable {
        let name: String
        let headline: String?
        let date: String?
        let ranks: [Rank]
        let droppedOut: [Lossy<Dropped>]?
    }
    struct Rank: Decodable {
        let current: Int
        let previous: Int?
        let recordSummary: String?
        let team: T
    }
    struct Dropped: Decodable { let team: T }
    struct T: Decodable {
        let id: String?
        let location: String
        let nickname: String?
    }
}

// MARK: - App model

enum GameState { case live, upcoming, final }

struct Side {
    let teamID: String
    let name: String
    let rank: Int?      // 1...25 AP rank, nil if unranked (or if this is an NCAA Tournament game)
    let score: String?
    var record: String? = nil
    var seed: Int? = nil   // NCAA Tournament seed, 1...16
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

    /// Best AP rank or tournament seed in the game; tournament games all count as "top" games.
    var bestRank: Int { min(away.rank ?? away.seed ?? 99, home.rank ?? home.seed ?? 99) }
    var isRanked: Bool { bestRank <= 25 }
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

    /// A matchup worth circling: two AP top-10 teams, or in the NCAA Tournament two top-3 seeds
    /// or anything from the Elite 8 on. Finished games don't count.
    var isMarquee: Bool {
        guard state != .final else { return false }
        if let a = away.rank, let h = home.rank { return a <= 10 && h <= 10 }
        if let a = away.seed, let h = home.seed {
            return (a <= 3 && h <= 3) || ["ELITE 8", "FINAL FOUR", "CHAMPIONSHIP"].contains(round ?? "")
        }
        return false
    }
    /// Live, fourth quarter or overtime, 4:00 or less left, within one score (8 points).
    var isCloseLate: Bool {
        guard state == .live, period >= 4, clock <= 240, let m = margin else { return false }
        return m <= 8   // one possession
    }
    /// Live in the second half or overtime, with an unranked team leading a ranked one.
    var isUpsetBrewing: Bool {
        guard state == .live, period >= 2, !isHalftime,
              let a = Int(away.score ?? ""), let h = Int(home.score ?? "") else { return false }
        if let sa = away.seed, let sh = home.seed {
            // Tournament: a seed four or more lines worse is ahead.
            return (sa - sh >= 4 && a > h) || (sh - sa >= 4 && h > a)
        }
        guard (away.rank == nil) != (home.rank == nil) else { return false }
        return away.rank == nil ? a > h : h > a
    }
}

struct RankedTeam {
    let rank: Int
    let name: String
    let record: String
    var id: String = ""
    var previous: Int? = nil   // rank in the last poll; 0 or nil if it wasn't ranked
}

/// One week's AP poll.
struct AppPoll {
    let id: String          // changes every week
    let title: String       // e.g. "Week 3"
    let date: Date?
    let teams: [RankedTeam]
    let dropped: [(id: String, name: String)]
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

    static func get<T: Decodable>(_ type: T.Type, _ url: String) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: URL(string: url)!)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// One NFL week of the schedule: season type 1 preseason, 2 regular season, 3 postseason.
    struct Week: Equatable {
        let type: Int
        let number: Int
        let start: Date
        let end: Date
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
                    weeks.append(Week(type: type, number: n, start: s, end: en))
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

    /// The week that contains `day`.
    static func fetchBoard(on day: Date, group: Int = 0) async throws -> [Game] {
        let weeks = try await calendar()
        return try await fetchWeek(weeks[week(containing: day, in: weeks)])
    }

    /// What the ticker treats as "today": this NFL week's games, finished ones included.
    /// (`group` and `alsoTeams` are kept for the callers; NFL has no conference filter.)
    static func fetchToday(group: Int = 0, alsoTeams: Set<String> = []) async throws -> [Game] {
        try await fetchBoard(on: Date())
    }

    /// Next week's games, as element 0 (`days` is ignored). A failed fetch comes back empty.
    static func fetchLookahead(days: Int, group: Int = 0) async -> [[Game]] {
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

    /// NFL has no conference filter or poll in v1 (a division filter may come later).
    static func fetchConferences() async throws -> [Conference] { [] }
    static func fetchTop25() async throws -> [RankedTeam] { [] }
    static func fetchPoll() async throws -> AppPoll { AppPoll(id: "", title: "", date: nil, teams: [], dropped: []) }

    /// "NCAA Men's Basketball Championship - East Region - Sweet 16" -> "SWEET 16".
    private static func roundLabel(_ headline: String) -> String? {
        guard let last = headline.components(separatedBy: " - ").last, !last.contains("Championship") || last == "National Championship"
        else { return nil }
        return (last == "National Championship" ? "CHAMPIONSHIP" : last).uppercased()
    }

    private static func makeGame(_ e: Ev) -> Game? {
        guard let comp = e.competitions.first,
              let status = e.status ?? comp.status,
              let away = comp.competitors.first(where: { $0.homeAway == "away" }),
              let home = comp.competitors.first(where: { $0.homeAway == "home" }) else { return nil }

        let headline = comp.notes?.compactMap { $0.value?.headline }.first ?? ""
        func side(_ c: CompetitorJSON) -> Side {
            Side(teamID: c.team.id,
                 name: c.team.shortDisplayName ?? c.team.displayName,
                 rank: nil,
                 score: c.score,
                 record: c.record,
                 seed: nil,
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
        _ = headline   // postseason round labels come in a later phase
        game.period = status.period ?? 0
        game.clock = status.clock ?? 0
        game.isHalftime = status.type.name == "STATUS_HALFTIME"
        return game
    }
}

// MARK: - Box score

struct SummaryResponse: Decodable {
    let boxscore: Box?
    let plays: [Lossy<Play>]?
    struct Box: Decodable { let teams: [TeamBox]?; let players: [PlayersBox]? }
    struct TeamRef: Decodable { let id: String }
    struct TeamBox: Decodable { let team: TeamRef; let statistics: [Stat]? }
    struct Stat: Decodable { let label: String?; let displayValue: String? }
    struct PlayersBox: Decodable { let team: TeamRef; let statistics: [Group]? }
    struct Group: Decodable { let labels: [String]?; let athletes: [Athlete]? }
    struct Athlete: Decodable { let athlete: Person; let stats: [String]? }
    struct Person: Decodable { let displayName: String? }
    struct Play: Decodable {
        let text: String?
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
    /// A game's team stats, top scorers and latest play. About 400 KB, so only fetched on a click.
    static func fetchBoxScore(gameID: String) async throws -> BoxScore {
        let r = try await get(SummaryResponse.self, "\(base)/summary?event=\(gameID)")
        var box = BoxScore()
        let keep = [("FG", "FG"), ("3PT", "3PT"), ("FT", "FT"), ("Rebounds", "REB"), ("Assists", "AST"), ("Turnovers", "TO")]
        for t in r.boxscore?.teams ?? [] {
            var line = BoxScore.Line()
            for (key, label) in keep {
                if let v = t.statistics?.first(where: { $0.label == key })?.displayValue { line.stats.append((label, v)) }
            }
            box.lines[t.team.id] = line
        }
        for pb in r.boxscore?.players ?? [] {
            guard let g = pb.statistics?.first, let labels = g.labels else { continue }
            let iP = labels.firstIndex(of: "PTS"), iR = labels.firstIndex(of: "REB"), iA = labels.firstIndex(of: "AST")
            func val(_ a: SummaryResponse.Athlete, _ i: Int?) -> Int {
                guard let i, let st = a.stats, st.indices.contains(i) else { return 0 }
                return Int(st[i]) ?? 0
            }
            let top = (g.athletes ?? []).sorted { val($0, iP) > val($1, iP) }.prefix(2).filter { val($0, iP) > 0 }
            box.lines[pb.team.id, default: BoxScore.Line()].leaders = top.map {
                "\($0.athlete.displayName ?? "?")  \(val($0, iP)) pts, \(val($0, iR)) reb, \(val($0, iA)) ast"
            }
        }
        if let p = r.plays?.compactMap({ $0.value }).last(where: { !($0.text ?? "").isEmpty }) {
            let n = p.period?.number ?? 0
            let half = n == 1 ? "1st" : (n == 2 ? "2nd" : (n > 2 ? "OT" : ""))
            box.lastPlay = [p.clock?.displayValue, half].compactMap { $0 }.joined(separator: " ") + " · " + (p.text ?? "")
        }
        return box
    }
}
