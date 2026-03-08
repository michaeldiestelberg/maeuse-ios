import SwiftUI
import SwiftData

@main
struct MaeuseApp: App {
    @AppStorage("maeuse.colorScheme") private var colorSchemePreference: String = "system"
    @AppStorage("maeuse.onboarding-hidden") private var onboardingHidden: Bool = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(resolvedColorScheme)
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
