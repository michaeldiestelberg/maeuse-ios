import SwiftUI
import SwiftData

@main
struct MaeuseApp: App {
    @AppStorage("maeuse.colorScheme") private var colorSchemePreference: String = "system"
    @AppStorage("maeuse.onboarding-hidden") private var onboardingHidden: Bool = false
    @State private var languageManager = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(resolvedColorScheme)
                .environment(\.locale, languageManager.activeLocale)
                .modelContainer(for: Expense.self)
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
