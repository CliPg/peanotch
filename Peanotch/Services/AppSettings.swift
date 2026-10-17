import Combine
import Foundation

/// Basic app settings, persisted to UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// "system" | "zh" | "en"
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: Self.languageKey) }
    }
    /// "click" | "hover" — how the notch dashboard opens
    @Published var openMode: String {
        didSet { UserDefaults.standard.set(openMode, forKey: Self.openModeKey) }
    }
    /// "c" | "f"
    @Published var tempUnit: String {
        didSet { UserDefaults.standard.set(tempUnit, forKey: Self.tempUnitKey) }
    }
    @Published var clock24h: Bool {
        didSet { UserDefaults.standard.set(clock24h, forKey: Self.clock24hKey) }
    }
    /// Trackpad haptic tick when the dashboard opens
    @Published var hapticFeedback: Bool {
        didSet { UserDefaults.standard.set(hapticFeedback, forKey: Self.hapticKey) }
    }
    /// Show the sports schedule card on the dashboard
    @Published var showSportsCard: Bool {
        didSet { UserDefaults.standard.set(showSportsCard, forKey: Self.sportsCardKey) }
    }
    /// Per-sport: only show favorite-team games in the calendar schedule
    @Published var onlyFavoriteNbaGames: Bool {
        didSet { UserDefaults.standard.set(onlyFavoriteNbaGames, forKey: Self.onlyFavoriteNbaKey) }
    }
    @Published var onlyFavoriteCs2Games: Bool {
        didSet { UserDefaults.standard.set(onlyFavoriteCs2Games, forKey: Self.onlyFavoriteCs2Key) }
    }
    /// Chinese team names (as used by the Hupu data source), order-stable
    @Published var favoriteTeams: [String] {
        didSet {
            let unique = Array(NSOrderedSet(array: favoriteTeams)) as? [String] ?? favoriteTeams
            UserDefaults.standard.set(unique, forKey: Self.favoriteTeamsKey)
        }
    }

    private static let languageKey = "peanotch.settings.language"
    private static let openModeKey = "peanotch.settings.openMode"
    private static let tempUnitKey = "peanotch.settings.tempUnit"
    private static let clock24hKey = "peanotch.settings.clock24h"
    private static let hapticKey = "peanotch.settings.haptic"
    private static let sportsCardKey = "peanotch.settings.showSportsCard"
    private static let onlyFavoriteNbaKey = "peanotch.settings.onlyFavoriteNba"
    private static let onlyFavoriteCs2Key = "peanotch.settings.onlyFavoriteCs2"
    private static let legacyOnlyFavoriteKey = "peanotch.settings.onlyFavoriteGames"
    private static let favoriteTeamsKey = "peanotch.settings.favoriteTeams"

    var resolvedLanguage: String {
        if language == "zh" || language == "en" { return language }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en"
    }

    /// The favorites-only filter is a per-sport switch in settings.
    func onlyFavorites(for sport: SportsService.Sport) -> Bool {
        sport == .cs2 ? onlyFavoriteCs2Games : onlyFavoriteNbaGames
    }

    private init() {
        let defaults = UserDefaults.standard
        language = defaults.string(forKey: Self.languageKey) ?? "system"
        openMode = defaults.string(forKey: Self.openModeKey) ?? "click"
        tempUnit = defaults.string(forKey: Self.tempUnitKey) ?? "c"
        clock24h = defaults.object(forKey: Self.clock24hKey) as? Bool ?? true
        hapticFeedback = defaults.object(forKey: Self.hapticKey) as? Bool ?? true
        showSportsCard = defaults.object(forKey: Self.sportsCardKey) as? Bool ?? false
        // Migrate the old single toggle to both per-sport switches.
        if let legacy = defaults.object(forKey: Self.legacyOnlyFavoriteKey) as? Bool,
           defaults.object(forKey: Self.onlyFavoriteNbaKey) == nil,
           defaults.object(forKey: Self.onlyFavoriteCs2Key) == nil {
            onlyFavoriteNbaGames = legacy
            onlyFavoriteCs2Games = legacy
        } else {
            onlyFavoriteNbaGames = defaults.object(forKey: Self.onlyFavoriteNbaKey) as? Bool ?? false
            onlyFavoriteCs2Games = defaults.object(forKey: Self.onlyFavoriteCs2Key) as? Bool ?? false
        }
        favoriteTeams = defaults.stringArray(forKey: Self.favoriteTeamsKey) ?? []
    }
}

/// Tiny localization helper: L10n.t("中文", "English").
enum L10n {
    static func t(_ zh: String, _ en: String) -> String {
        AppSettings.shared.resolvedLanguage == "en" ? en : zh
    }
}
