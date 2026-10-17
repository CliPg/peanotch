import Combine
import Foundation

/// Game schedules scraped from free domestic sources:
///   - NBA  — Hupu's mobile schedule page (m.hupu.com/nba/schedule), JSON
///     embedded in the SSR HTML (~10-day window around today)
///   - CS2  — 5E's public esports-data CDN (esports-data.5eplaycdn.com),
///     no login required; S-tier tournaments only per product decision
///
/// Refresh policy:
///   - normally fetch once a day;
///   - while a favorite team's game or an S-tier CS2 match is live, poll
///     every 2 minutes;
///   - otherwise wake up shortly after the next such game tips off.
final class SportsService: ObservableObject {
    enum Sport: Equatable {
        case nba
        case cs2
    }

    enum GameStatus: Equatable {
        case scheduled
        case live
        case finished
    }

    struct Game: Identifiable, Equatable {
        let id: String
        let sport: Sport
        let startTime: Date
        let homeTeam: String
        let awayTeam: String
        let homeScore: Int?
        let awayScore: Int?
        let status: GameStatus
        /// Live CS2 only: current map + round score, e.g. "Anubis 6-2".
        var liveDetail: String? = nil
    }

    /// Chinese team names exactly as they appear in the Hupu data (the
    /// favorites list is matched against these strings).
    static let nbaTeamsEast = ["凯尔特人", "篮网", "尼克斯", "76人", "猛龙",
                               "公牛", "骑士", "活塞", "步行者", "雄鹿",
                               "老鹰", "黄蜂", "热火", "魔术", "奇才"]
    static let nbaTeamsWest = ["独行侠", "火箭", "灰熊", "鹈鹕", "马刺",
                               "掘金", "森林狼", "雷霆", "开拓者", "爵士",
                               "勇士", "快船", "湖人", "太阳", "国王"]

    /// HLTV top-20 CS2 teams, named exactly as 5E's data spells them so the
    /// favorite matching works. Display aliases for long names live in the
    /// settings UI.
    static let cs2TopTeams = ["Vitality", "MOUZ", "Spirit", "Falcons", "Mongolz",
                              "Aurora", "G2", "NAVI", "FURIA", "Liquid",
                              "FaZe", "Virtus.pro", "Astralis", "TYLOO", "Legacy",
                              "Nemiga", "MIBR", "Ninjas in Pyjamas", "9z", "FUT"]

    /// Short chip labels for verbose CS2 team names (full name is stored).
    static let cs2TeamAliases = ["Ninjas in Pyjamas": "NiP"]

    @Published private(set) var games: [Game] = []
    @Published private(set) var lastUpdated: Date?

    private var fetchTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    func start() {
        // React to settings changes: fetch when the card gets enabled, and
        // re-evaluate the polling cadence when the favorite teams change.
        AppSettings.shared.$showSportsCard
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.fetchNow()
                } else {
                    self?.fetchTimer?.invalidate()
                    self?.fetchTimer = nil
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$favoriteTeams
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard AppSettings.shared.showSportsCard else { return }
                self?.fetchNow()
            }
            .store(in: &cancellables)

        if AppSettings.shared.showSportsCard {
            fetchNow()
        }
    }

    // MARK: - Fetching

    private func fetchNow() {
        var nbaGames: [Game]?
        var cs2Games: [Game]?
        let group = DispatchGroup()

        group.enter()
        fetchHupu { group.leave(); nbaGames = $0 }

        group.enter()
        fetchCS2 { group.leave(); cs2Games = $0 }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            // nil = request/parse failed (keep whatever we had); [] = genuinely
            // no games. Only overwrite when at least one source answered.
            if nbaGames != nil || cs2Games != nil {
                var all = (nbaGames ?? []) + (cs2Games ?? [])
                all.sort { $0.startTime < $1.startTime }
                self.games = all
                self.lastUpdated = Date()
                Diagnostics.record("sports: fetched nba=\(nbaGames?.count ?? -1) cs2=\(cs2Games?.count ?? -1)")
            } else {
                Diagnostics.record("sports: all sources failed, keeping \(self.games.count) stale games")
            }
            self.scheduleNextFetch()
        }
    }

    private func requestJSON(_ url: URL, completion: @escaping ([String: Any]?) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, _, _ in
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            DispatchQueue.main.async { completion(object) }
        }.resume()
    }

    // MARK: NBA (Hupu)

    private func fetchHupu(completion: @escaping ([Game]?) -> Void) {
        var request = URLRequest(url: URL(string: "https://m.hupu.com/nba/schedule")!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, _, _ in
            let games = data.flatMap(Self.parseHupu)
            DispatchQueue.main.async { completion(games) }
        }.resume()
    }

    /// Extracts the embedded `__NEXT_DATA__` JSON and flattens the day blocks
    /// into a single game list, keeping NBA only (lid == "1").
    private static func parseHupu(_ data: Data) -> [Game]? {
        guard let html = String(data: data, encoding: .utf8),
              let range = html.range(of: #"<script id="__NEXT_DATA__"[^>]*>"#, options: .regularExpression) else { return nil }
        let afterTag = html[range.upperBound...]
        guard let end = afterTag.range(of: "</script>") else { return nil }
        guard let jsonData = String(afterTag[..<end.lowerBound]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }

        var games: [Game] = []
        for dayBlock in findGameLists(root) {
            guard let matches = dayBlock["matchList"] as? [[String: Any]] else { continue }
            for match in matches {
                if let game = game(from: match) {
                    games.append(game)
                }
            }
        }
        guard !games.isEmpty else { return nil }
        return games.sorted { $0.startTime < $1.startTime }
    }

    private static func findGameLists(_ node: Any) -> [[String: Any]] {
        if let dict = node as? [String: Any] {
            if let list = dict["gameList"] as? [[String: Any]] {
                return list
            }
            for value in dict.values {
                let found = findGameLists(value)
                if !found.isEmpty { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                let found = findGameLists(value)
                if !found.isEmpty { return found }
            }
        }
        return []
    }

    private static func game(from match: [String: Any]) -> Game? {
        guard let matchTime = match["matchTime"] as? String,
              let startTime = timeFormatter.date(from: matchTime),
              let home = match["homeTeamName"] as? String,
              let away = match["awayTeamName"] as? String,
              let id = (match["matchId"] as? String) ?? (match["gdcId"].flatMap { "\($0)" }) else { return nil }
        // lid "1" is NBA on Hupu; skip other competitions on the page.
        if let lid = match["lid"] as? String, lid != "1" { return nil }

        let statusChinese = (match["matchStatusChinese"] as? String) ?? ""
        let matchStatus = (match["matchStatus"] as? String) ?? ""
        let now = Date()
        let status: GameStatus
        if matchStatus == "COMPLETED" || statusChinese.contains("结束") {
            status = .finished
        } else if statusChinese.contains("进行") || matchStatus == "PROCESSING" {
            status = .live
        } else if now >= startTime, now < startTime.addingTimeInterval(4 * 3600) {
            // Server may lag behind tipoff; treat started-and-unfinished as live.
            status = .live
        } else {
            status = .scheduled
        }

        return Game(id: id,
                    sport: .nba,
                    startTime: startTime,
                    homeTeam: home,
                    awayTeam: away,
                    homeScore: match["homeScore"] as? Int,
                    awayScore: match["awayScore"] as? Int,
                    status: status)
    }

    // MARK: CS2 (5E esports-data CDN, S-tier only)

    /// 5E grade values: "2" = S级, "3" = A级, "4" = B级, "5" = C级, "6" = 资格赛.
    /// "1" is reserved for even bigger events (Majors) — include it too.
    private static func cs2IsSTier(_ match: [String: Any]) -> Bool {
        let tt = match["tt_info"] as? [String: Any]
        let grade = (match["grade"] as? String) ?? (tt?["grade"] as? String) ?? ""
        if grade == "1" || grade == "2" { return true }
        if let label = tt?["grade_label"] as? String, label.contains("S") { return true }
        return false
    }

    private static func cs2Score(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let string = value as? String { return Int(string) }
        return nil
    }

    /// Maps one 5E match record (preview/result/hot share the shape) to a Game.
    /// Status: live (state.live_status), finished (scores/end_time), else scheduled.
    /// preview/result carry `start_time` ("2026-10-18 01:00:00", local time);
    /// hot_match only has `plan_ts` (unix seconds as string).
    private static func cs2Game(from match: [String: Any]) -> Game? {
        let startTime = (match["start_time"] as? String).flatMap { timeFormatter.date(from: $0) }
            ?? (match["plan_ts"] as? String).flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
        guard let startTime,
              let t1 = (match["t1_info"] as? [String: Any])?["disp_name"] as? String,
              let t2 = (match["t2_info"] as? [String: Any])?["disp_name"] as? String,
              let id = match["id"] as? String else { return nil }
        // Bracket placeholders without either team known carry no information.
        guard t1 != "TBD" || t2 != "TBD" else { return nil }

        var s1 = cs2Score(match["t1_score"])
        var s2 = cs2Score(match["t2_score"])
        var liveDetail: String?
        var status: GameStatus = (s1 != nil || !(match["end_time"] as? String ?? "").isEmpty) ? .finished : .scheduled
        if let state = match["state"] as? [String: Any] {
            // 5E sends live_status as a STRING ("1"); be liberal about it.
            let liveRaw = state["live_status"]
            let isLive = (liveRaw as? String) == "1" || (liveRaw as? Int) == 1
            if isLive { status = .live }
            s1 = s1 ?? cs2Score(state["t1_score"])
            s2 = s2 ?? cs2Score(state["t2_score"])
            // 小分: the in-progress map's round score (bout status "1").
            if isLive,
               let bouts = state["bout_states"] as? [[String: Any]],
               let current = bouts.first(where: { ($0["status"] as? String) == "1" }),
               let r1 = cs2Score(current["t1_score"]), let r2 = cs2Score(current["t2_score"]) {
                let mapName = (current["map_name"] as? String) ?? ""
                liveDetail = mapName.isEmpty ? "\(r1)-\(r2)" : "\(mapName) \(r1)-\(r2)"
            }
        }

        return Game(id: id,
                    sport: .cs2,
                    startTime: startTime,
                    homeTeam: t2,
                    awayTeam: t1,
                    homeScore: s2,
                    awayScore: s1,
                    status: status,
                    liveDetail: liveDetail)
    }

    private func fetchCS2(completion: @escaping ([Game]?) -> Void) {
        let base = "https://esports-data.5eplaycdn.com/v1/api/csgo/platform"
        let dayFormat = DateFormatter()
        dayFormat.dateFormat = "yyyy-MM-dd"
        let today = Calendar.current.startOfDay(for: Date())
        let start = dayFormat.string(from: today.addingTimeInterval(-2 * 86400))
        let end = dayFormat.string(from: today.addingTimeInterval(9 * 86400))

        // Each source keyed by match id; merged afterwards with a fixed
        // priority (hot/live > result > preview) instead of arrival order.
        var preview: [String: [String: Any]] = [:]
        var results: [String: [String: Any]] = [:]
        var hot: [String: [String: Any]] = [:]
        var anySuccess = false
        let lock = NSLock()
        let group = DispatchGroup()

        func list(from json: [String: Any]?) -> [[String: Any]]? {
            (json?["data"] as? [String: Any])?["match_list"] as? [[String: Any]]
        }

        group.enter()
        requestJSON(URL(string: "\(base)/matches/preview?start_date=\(start)&end_date=\(end)")!) { json in
            let matches = list(from: json)
            lock.lock()
            if matches != nil { anySuccess = true }
            for match in matches ?? [] where Self.cs2IsSTier(match) {
                if let id = match["id"] as? String { preview[id] = match }
            }
            lock.unlock()
            group.leave()
        }
        group.enter()
        requestJSON(URL(string: "\(base)/matches/result?limit=100&page=1")!) { json in
            let matches = list(from: json)
            lock.lock()
            if matches != nil { anySuccess = true }
            for match in matches ?? [] where Self.cs2IsSTier(match) {
                if let id = match["id"] as? String { results[id] = match }
            }
            lock.unlock()
            group.leave()
        }
        group.enter()
        requestJSON(URL(string: "\(base)/hot_match")!) { json in
            // hot_match wraps each match as {mc_info, state, tt_info}; flatten
            // to the shared shape so the same mapper applies.
            let matches = (((json?["data"] as? [String: Any])?["matches"] as? [[String: Any]])?
                .compactMap { entry -> [String: Any]? in
                    guard var mc = entry["mc_info"] as? [String: Any] else { return nil }
                    if let state = entry["state"] as? [String: Any] { mc["state"] = state }
                    if let tt = entry["tt_info"] as? [String: Any], mc["tt_info"] == nil { mc["tt_info"] = tt }
                    return mc
                })
            lock.lock()
            if matches != nil { anySuccess = true }
            for match in matches ?? [] where Self.cs2IsSTier(match) {
                if let id = match["id"] as? String { hot[id] = match }
            }
            lock.unlock()
            group.leave()
        }

        group.notify(queue: .main) {
            guard anySuccess else {
                completion(nil)
                return
            }
            var merged = preview
            for (id, record) in results { merged[id] = record }
            for (id, record) in hot { merged[id] = record }
            let games = merged.values.compactMap { Self.cs2Game(from: $0) }
            completion(games.sorted { $0.startTime < $1.startTime })
        }
    }

    // MARK: - Refresh cadence

    private func scheduleNextFetch() {
        fetchTimer?.invalidate()
        guard AppSettings.shared.showSportsCard else {
            fetchTimer = nil
            return
        }

        let favorites = Set(AppSettings.shared.favoriteTeams)
        // Tracked for fast polling: favorite NBA teams + S-tier CS2 matches.
        let trackedGames = games.filter {
            favorites.contains($0.homeTeam) || favorites.contains($0.awayTeam) || $0.sport == .cs2
        }

        let interval: TimeInterval
        if trackedGames.contains(where: { $0.status == .live }) {
            interval = 2 * 60
        } else if let nextTipoff = trackedGames
            .filter({ $0.status == .scheduled && $0.startTime > Date() })
            .map(\.startTime)
            .min(), nextTipoff.timeIntervalSinceNow < 24 * 3600 {
            // Wake up two minutes after the next favorite game starts so live
            // polling kicks in — but never wait longer than a day.
            interval = min(24 * 3600, max(60, nextTipoff.timeIntervalSinceNow + 120))
        } else {
            interval = 24 * 3600
        }
        Diagnostics.record("sports: next fetch in \(Int(interval / 60)) min")
        fetchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.fetchNow()
        }
    }

    // MARK: - Card helpers

    func involvesFavorite(_ game: Game, favorites: Set<String>) -> Bool {
        favorites.contains(game.homeTeam) || favorites.contains(game.awayTeam)
    }
}
