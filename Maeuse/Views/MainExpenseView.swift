import SwiftUI
import SwiftData

/// The primary view: header, month nav, summary card, expense list, FABs
struct MainExpenseView: View {
    @Bindable var listVM: ExpenseListViewModel
    @Bindable var editorVM: ExpenseEditorViewModel
    @Bindable var voiceVM: VoiceModeViewModel
    @Bindable var settingsVM: SettingsViewModel

    let expenses: [Expense]

    @AppStorage("maeuse.onboarding-hidden") private var onboardingHidden: Bool = false
    @AppStorage("maeuse.colorScheme") private var colorSchemePreference: String = "system"
    @State private var showOnboardingAgain = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    private var filtered: [Expense] {
        listVM.filteredExpenses(from: expenses)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Background
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerBar

                // Month Navigation + Summary
                ScrollView {
                    VStack(spacing: 16) {
                        monthNavigation
                        summaryCard
                        expenseList
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 100) // Space for FABs
                }
            }

            // FAB Stack
            fabStack
        }
        .sheet(isPresented: $editorVM.isPresented) {
            ExpenseEditorSheet(viewModel: editorVM)
        }
        .fullScreenCover(isPresented: $voiceVM.isPresented) {
            VoiceSheet(viewModel: voiceVM)
        }
        .sheet(isPresented: $settingsVM.isPresented) {
            SettingsSheet(viewModel: settingsVM, expenses: expenses)
        }
        .sheet(isPresented: $showOnboardingAgain) {
            OnboardingView(isPresented: $showOnboardingAgain, onDismiss: { _ in })
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [Color(hex: "0a0a0a"), Color(hex: "050505"), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [Color(hex: "f4f3ef"), Color(hex: "eae8e1"), Color(hex: "e4e2db")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            // Brand
            HStack(spacing: 8) {
                Image(systemName: "banknote")
                    .font(.title3)
                    .foregroundStyle(Color.maeusPrimary)

                Text("Mäuse")
                    .font(.title2.weight(.bold))
                    .tracking(-0.5)
            }

            Spacer()

            // Action Buttons
            HStack(spacing: 8) {
                // About (info) button
                Button {
                    showOnboardingAgain = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.body)
                        .foregroundStyle(Color.maeusTextTertiary)
                        .frame(width: 32, height: 32)
                }

                // Settings button
                Button {
                    settingsVM.isPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(Color.maeusTextTertiary)
                        .frame(width: 32, height: 32)
                }

                // Theme toggle
                Button {
                    toggleTheme()
                } label: {
                    Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                        .font(.body)
                        .foregroundStyle(Color.maeusPrimary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle().strokeBorder(Color(UIColor.separator).opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    // MARK: - Month Navigation

    private var monthNavigation: some View {
        HStack {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    listVM.previousMonth()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.maeusTextSecondary)
                    .frame(width: 36, height: 36)
            }

            Spacer()

            Text(listVM.monthLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.maeusText)

            Spacer()

            Button {
                withAnimation(.spring(duration: 0.3)) {
                    listVM.nextMonth()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.maeusTextSecondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(Color.maeusTextSecondary)
                Text(listVM.totalAmount(for: filtered).euroFormatted)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.maeusText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Partner's share")
                    .font(.caption)
                    .foregroundStyle(Color.maeusTextSecondary)
                Text(listVM.partnerTotal(for: filtered).euroFormatted)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.maeusPrimary)
            }
        }
        .padding(20)
        .glassSurface()
    }

    // MARK: - Expense List

    private var expenseList: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(Color.maeusTextTertiary)
                    Text("No expenses yet")
                        .font(.subheadline)
                        .foregroundStyle(Color.maeusTextSecondary)
                    Text("Tap + to add your first expense")
                        .font(.caption)
                        .foregroundStyle(Color.maeusTextTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.id) { expense in
                        ExpenseRow(expense: expense, listVM: listVM)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editorVM.prepareForEdit(expense)
                            }

                        if expense.id != filtered.last?.id {
                            Divider()
                                .padding(.leading, 52)
                                .opacity(0.3)
                        }
                    }
                }
                .padding(.vertical, 8)
                .glassSurface()
            }
        }
    }

    // MARK: - FAB Stack

    private var fabStack: some View {
        VStack(spacing: 12) {
            // Voice FAB (only when voice is enabled)
            if settingsVM.voiceSettings.isReady {
                Button {
                    voiceVM.open()
                } label: {
                    Image(systemName: "mic")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.maeusPrimary)
                }
                .buttonStyle(FABStyle(isPrimary: false))
            }

            // Add FAB
            Button {
                editorVM.prepareForNew()
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(FABStyle(isPrimary: true))
        }
        .padding(.trailing, 20)
        .padding(.bottom, 28)
    }

    // MARK: - Theme Toggle

    private func toggleTheme() {
        switch colorSchemePreference {
        case "system":
            colorSchemePreference = colorScheme == .dark ? "light" : "dark"
        case "light":
            colorSchemePreference = "dark"
        case "dark":
            colorSchemePreference = "light"
        default:
            colorSchemePreference = "system"
        }
    }
}
