import SwiftUI
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case german = "de"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .german: return "Deutsch"
        }
    }
}

@Observable
final class LanguageManager: @unchecked Sendable {
    static let shared = LanguageManager()

    var languagePreference: AppLanguage {
        get {
            let val = UserDefaults.standard.string(forKey: "maeuse.language") ?? "system"
            return AppLanguage(rawValue: val) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "maeuse.language")
            updateActiveLanguage()
        }
    }

    private(set) var activeLanguageCode: String = "en"

    private init() {
        updateActiveLanguage()

        NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateActiveLanguage()
        }
    }

    func updateActiveLanguage() {
        switch languagePreference {
        case .system:
            if let preferredLanguage = Locale.preferredLanguages.first {
                if preferredLanguage.hasPrefix("de") {
                    activeLanguageCode = "de"
                } else {
                    activeLanguageCode = "en"
                }
            } else {
                activeLanguageCode = "en"
            }
        case .english:
            activeLanguageCode = "en"
        case .german:
            activeLanguageCode = "de"
        }
    }

    var activeLocale: Locale {
        Locale(identifier: activeLanguageCode)
    }

    func localizedString(forKey key: String) -> String {
        guard let path = Bundle.main.path(forResource: activeLanguageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    func localizedString(forKey key: String, arguments: [CVarArg]) -> String {
        let format = localizedString(forKey: key)
        return String(format: format, locale: activeLocale, arguments: arguments)
    }
}

func loc(_ key: String) -> String {
    LanguageManager.shared.localizedString(forKey: key)
}

func loc(_ key: String, _ arguments: CVarArg...) -> String {
    LanguageManager.shared.localizedString(forKey: key, arguments: arguments)
}
