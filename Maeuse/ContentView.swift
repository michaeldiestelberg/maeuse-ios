import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("maeuse.onboarding-hidden") private var onboardingHidden: Bool = false
    @State private var showOnboarding: Bool = false

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
                expenses: allExpenses
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
    }
}
