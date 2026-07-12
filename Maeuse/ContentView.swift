import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("maeuse.onboarding-hidden") private var onboardingHidden: Bool = false
    @State private var showOnboarding: Bool = false
    @State private var languageManager = LanguageManager.shared

    @State private var listVM = ExpenseListViewModel()

    @State private var editorVM = ExpenseEditorViewModel()
    @State private var voiceVM = VoiceModeViewModel()
    @State private var settingsVM = SettingsViewModel()

    @Environment(\.modelContext) private var modelContext
    @Query private var allExpenses: [Expense]

    var body: some View {
        ZStack {
            MainExpenseView(
                listVM: listVM,
                editorVM: editorVM,
                voiceVM: voiceVM,
                settingsVM: settingsVM,
                expenses: allExpenses,
                onShowWelcomeGuide: {
                    showOnboarding = true
                }
            )

            if showOnboarding {
                OnboardingView(isPresented: $showOnboarding, onDismiss: { skipFuture in
                    if skipFuture {
                        onboardingHidden = true
                    }
                })
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.35), value: showOnboarding)
        .onAppear {
            if !onboardingHidden {
                showOnboarding = true
            }
        }
        .task {
            #if targetEnvironment(simulator)
            if screenshotScenario == nil {
                settingsVM.reconcileStoredAPIKey()
            } else {
                prepareScreenshotScenario()
            }
            #else
            settingsVM.reconcileStoredAPIKey()
            #endif
        }
    }

    #if targetEnvironment(simulator)
    private var screenshotScenario: String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--screenshot-") }
            .map { String($0.dropFirst("--screenshot-".count)) }
    }

    private func prepareScreenshotScenario() {
        guard let screenshotScenario else { return }

        onboardingHidden = true
        showOnboarding = false

        do {
            let existingExpenses = try modelContext.fetch(FetchDescriptor<Expense>())
            for expense in existingExpenses {
                modelContext.delete(expense)
            }
            try modelContext.save()

            for expense in screenshotExpenses() {
                modelContext.insert(expense)
            }
            try modelContext.save()
        } catch {
            assertionFailure("Could not prepare screenshot data: \(error)")
        }

        switch screenshotScenario {
        case "editor":
            editorVM.prepareForNew()
            editorVM.amountText = LanguageManager.shared.activeLanguageCode == "de" ? "84,30" : "84.30"
            editorVM.description = LanguageManager.shared.activeLanguageCode == "de" ? "Wocheneinkauf" : "Weekly groceries"
            editorVM.setPartnerFraction(0.5)
        case "settings":
            settingsVM.hasSavedVoiceAPIKey = true
            settingsVM.voiceSettings.apiKeySuffix = "7mQ2"
            settingsVM.voiceSettings.verifiedAt = Date()
            settingsVM.voiceSettings.consentVersion = VoiceSettings.currentConsentVersion
            settingsVM.voiceSettings.consentedAt = Date()
            settingsVM.voiceSettings.enabled = true
            settingsVM.isPresented = true
        case "voice":
            voiceVM.openScreenshotPreview()
        default:
            break
        }
    }

    private func screenshotExpenses() -> [Expense] {
        let german = LanguageManager.shared.activeLanguageCode == "de"
        let calendar = Calendar.current
        let now = Date()

        func date(daysAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        }

        return [
            Expense(id: "screenshot-1", amount: 84.30, desc: german ? "Wocheneinkauf" : "Weekly groceries", date: date(daysAgo: 1), splitMode: .percent, splitValue: 50),
            Expense(id: "screenshot-2", amount: 62.50, desc: german ? "Abendessen bei Luigi" : "Dinner at Luigi's", date: date(daysAgo: 3), splitMode: .percent, splitValue: 50),
            Expense(id: "screenshot-3", amount: 26.00, desc: german ? "Bahntickets" : "Train tickets", date: date(daysAgo: 5), splitMode: .percent, splitValue: 50),
            Expense(id: "screenshot-4", amount: 18.90, desc: german ? "Apotheke" : "Pharmacy", date: date(daysAgo: 7), splitMode: .fixed, splitValue: 10),
            Expense(id: "screenshot-5", amount: 14.20, desc: german ? "Haushaltsartikel" : "Household supplies", date: date(daysAgo: 9), splitMode: .percent, splitValue: 50)
        ]
    }
    #endif
}
