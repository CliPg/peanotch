import Combine
import Foundation

/// NBA game schedule scraped from Hupu's mobile schedule page
/// (https://m.hupu.com/nba/schedule). The page is server-rendered and embeds
/// the full schedule window (~10 days around today) as JSON inside a
/// `<script id="__NEXT_DATA__">` tag, so one plain GET is enough — domestic,
/// no proxy, no signing.
///
/// Refresh policy (per product decision):
///   - normally fetch once a day;
///   - while a favorite team's game is live, poll every 2 minutes;
///   - otherwise wake up shortly after the next favorite game tips off.
final class SportsService: ObservableObject {
    enum GameStatus: Equatable {
        case scheduled
        case live
        case finished
    }

    struct Game: Identifiable, Equatable {
        let id: String
        let startTime: Date
        let homeTeam: String
        let awayTeam: String
        let homeScore: Int?
        let awayScore: Int?
        let status: GameStatus
    }

    /// Chinese team names exactly as they appear in the Hupu data (the
    /// favorites list is matched against these strings).
    static let nbaTeamsEast = ["凯尔特人", "篮网", "尼克斯", "76人", "猛龙",
                               "公牛", "骑士", "活塞", "步行者", "雄鹿",
                               "老鹰", "黄蜂", "热火", "魔术", "奇才"]
    static let nbaTeamsWest = ["独行侠", "火箭", "灰熊", "鹈鹕", "马刺",
                               "掘金", "森林狼", "雷霆", "开拓者", "爵士",
                               "勇士", "快船", "湖人", "太阳", "国王"]

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
        var request = URLRequest(url: URL(string: "https://m.hupu.com/nba/schedule")!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let startedAt = Date()
        session.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data, let games = Self.parse(data) {
                    self.games = games
                    self.lastUpdated = Date()
                    Diagnostics.record("sports: fetched \(games.count) games in \(Int(Date().timeIntervalSince(startedAt) * 1000))ms")
                } else {
                    Diagnostics.record("sports: fetch failed (\(error.map(String.init(describing:)) ?? "parse error"))")
                    // Keep stale data; retry sooner than the daily cadence.
                }
                self.scheduleNextFetch()
            }
        }.resume()
    }

    /// Extracts the embedded `__NEXT_DATA__` JSON and flattens the day blocks
    /// into a single game list, keeping NBA only (lid == "1").
    private static func parse(_ data: Data) -> [Game]? {
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
                    startTime: startTime,
                    homeTeam: home,
                    awayTeam: away,
                    homeScore: match["homeScore"] as? Int,
                    awayScore: match["awayScore"] as? Int,
                    status: status)
    }

    // MARK: - Refresh cadence

    private func scheduleNextFetch() {
        fetchTimer?.invalidate()
        guard AppSettings.shared.showSportsCard else {
            fetchTimer = nil
            return
        }

        let favorites = Set(AppSettings.shared.favoriteTeams)
        let favoriteGames = games.filter { favorites.contains($0.homeTeam) || favorites.contains($0.awayTeam) }

        let interval: TimeInterval
        if favoriteGames.contains(where: { $0.status == .live }) {
            interval = 2 * 60
        } else if let nextTipoff = favoriteGames
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
