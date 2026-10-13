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

    private static let languageKey = "peanotch.settings.language"
    private static let openModeKey = "peanotch.settings.openMode"
    private static let tempUnitKey = "peanotch.settings.tempUnit"
    private static let clock24hKey = "peanotch.settings.clock24h"

    var resolvedLanguage: String {
        if language == "zh" || language == "en" { return language }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en"
    }

    private init() {
        let defaults = UserDefaults.standard
        language = defaults.string(forKey: Self.languageKey) ?? "system"
        openMode = defaults.string(forKey: Self.openModeKey) ?? "click"
        tempUnit = defaults.string(forKey: Self.tempUnitKey) ?? "c"
        clock24h = defaults.object(forKey: Self.clock24hKey) as? Bool ?? true
    }
}

/// Tiny localization helper: L10n.t("中文", "English").
enum L10n {
    static func t(_ zh: String, _ en: String) -> String {
        AppSettings.shared.resolvedLanguage == "en" ? en : zh
    }
}
