import SwiftUI

struct MainExpenseView: View {
    @Bindable var listVM: ExpenseListViewModel
    @Bindable var editorVM: ExpenseEditorViewModel
    @Bindable var voiceVM: VoiceModeViewModel
    @Bindable var settingsVM: SettingsViewModel
    let expenses: [Expense]
    let onShowWelcomeGuide: () -> Void
    let onCaptureModalDismissed: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var totalFontSize = 42

    private var filtered: [Expense] { listVM.filteredExpenses(from: expenses) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PrismBackground()
            GeometryReader { geometry in
                let wide = geometry.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize
                let short = geometry.size.height < 500
                VStack(spacing: 0) {
                    header(compactActions: short).padding(.horizontal, 22).padding(.top, 12)
                    monthContent(wide: wide)
                }
                .frame(maxWidth: 1120)
                .frame(maxWidth: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !short {
                        HStack {
                            Spacer()
                            fabStack
                        }
                        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 16)
                        .background(Color.maeusBackground)
                    }
                }
            }
        }
        .fontDesign(.rounded)
        .sheet(isPresented: $editorVM.isPresented, onDismiss: onCaptureModalDismissed) {
            ExpenseEditorSheet(viewModel: editorVM)
        }
        .fullScreenCover(isPresented: $voiceVM.isPresented, onDismiss: onCaptureModalDismissed) {
            VoiceSheet(viewModel: voiceVM)
        }
        .sheet(isPresented: $settingsVM.isChoosingVoiceMode, onDismiss: { settingsVM.modeChoiceDismissed(); onCaptureModalDismissed() }) {
            VoiceModeSelectionView(viewModel: settingsVM) { provider in
                settingsVM.confirmVoiceMode(provider, openSetup: true)
            } onCancel: { settingsVM.isChoosingVoiceMode = false }
        }
        .sheet(isPresented: $settingsVM.isPresented, onDismiss: onCaptureModalDismissed) {
            SettingsSheet(
                viewModel: settingsVM,
                expenses: expenses,
                onShowWelcomeGuide: onShowWelcomeGuide
            )
        }
    }

    private func header(compactActions: Bool) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image("CoinMouseMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                    .accessibilityHidden(true)
                Text("Mäuse").font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(Color.maeusForeground)
            }
            Spacer()
            if compactActions { fabStack.padding(.trailing, 12) }
            Button { settingsVM.isPresented = true } label: {
                MaeuseSettingsIcon().frame(width: 38, height: 38)
            }
            .buttonStyle(StampedButtonStyle(fill: .maeusSurface, foreground: .maeusForeground, cornerRadius: 19, borderColor: .maeusCardBorder, shadow: 3, shadowColor: Color(hex: "E8A800")))
            .accessibilityLabel(loc("Settings"))
        }
    }

    private func monthContent(wide: Bool) -> some View {
        // All navigation and draft state belongs to the models above this
        // stateless arrangement; rebuilding columns cannot reset an entry.
        ScrollView {
            Group {
                if wide {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(spacing: 20) {
                            summaryCard
                            splitOverview
                        }
                        .frame(width: 320)
                        expenseList
                    }
                } else {
                    VStack(spacing: 20) {
                        summaryCard
                        expenseList
                    }
                }
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 24)
        }
        .accessibilityIdentifier("expense-ledger")
    }

    private var expenseList: some View {
        LazyVStack(spacing: 12) {
            if filtered.isEmpty { emptyState.padding(.top, 44) }
            else {
                ForEach(filtered, id: \.id) { expense in
                    Button { editorVM.prepareForEdit(expense) } label: {
                        ExpenseRow(expense: expense, listVM: listVM)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("expense-\(expense.id)")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var splitOverview: some View {
        CheeseCard(cornerRadius: 22, shadow: 3) {
            VStack(alignment: .leading, spacing: 16) {
                Text(loc("MonthlySplit"))
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                shareTotal(loc("You"), amount: max(0, listVM.totalAmount(for: filtered) - listVM.partnerTotal(for: filtered)))
                shareTotal(loc("Partner"), amount: listVM.partnerTotal(for: filtered))
                Text(loc("ExpenseCount", filtered.count))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.maeusTextSecondary)
            }
            .foregroundStyle(Color.maeusForeground)
            .padding(20)
        }
        .accessibilityIdentifier("monthly-split")
    }

    private func shareTotal(_ title: String, amount: Double) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.maeusTextSecondary)
            Spacer()
            Text(amount.euroFormatted).monospacedDigit()
        }
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .accessibilityElement(children: .combine)
    }

    private var summaryCard: some View {
        CheeseCard(cornerRadius: 26, shadow: 6, fill: .maeusCheese, borderColor: .maeusInk) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    monthButton(direction: -1)
                    Spacer()
                    Text(listVM.monthLabel.uppercased()).font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1)
                    Spacer()
                    monthButton(direction: 1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(listVM.totalAmount(for: filtered).euroFormatted)
                        .font(.system(size: totalFontSize, weight: .heavy, design: .rounded)).tracking(-1.5).monospacedDigit()
                        .minimumScaleFactor(0.65).lineLimit(1)
                    ViewThatFits(in: .horizontal) {
                        owedAmount(horizontal: true)
                        owedAmount(horizontal: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.maeusInk).padding(.horizontal, 22).padding(.vertical, 20)
            .overlay {
                GeometryReader { geometry in
                    FloatingCheeseHole(size: 34, duration: 7, stroke: .maeusInk)
                        .position(x: geometry.size.width - 53, y: 5)
                    FloatingCheeseHole(size: 14, duration: 8, delay: 2, stroke: .maeusInk)
                        .position(x: geometry.size.width - 103, y: 8)
                    FloatingCheeseHole(size: 22, duration: 9, delay: 1, stroke: .maeusInk)
                        .position(x: geometry.size.width - 3, y: geometry.size.height - 25)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private func owedAmount(horizontal: Bool) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        return layout {
            Text(loc("MausOwesYou"))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            Text(listVM.partnerTotal(for: filtered).euroFormatted)
                .font(.system(.subheadline, design: .rounded, weight: .heavy)).monospacedDigit()
                .foregroundStyle(Color.maeusCheese).padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.maeusInk, in: RoundedRectangle(cornerRadius: 8))
                .contentTransition(.numericText())
        }
    }

    private func monthButton(direction newDirection: CGFloat) -> some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.35)) {
                newDirection < 0 ? listVM.previousMonth() : listVM.nextMonth()
            }
        } label: {
            MaeuseChevronIcon(pointsRight: newDirection > 0).frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel(newDirection < 0 ? loc("PreviousMonth") : loc("NextMonth"))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            MouseCoin(size: 72, fill: .maeusSurface) {
                Text("?").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Color.maeusTextTertiary)
            }
            Text(loc("TrapEmpty")).font(.system(.headline, design: .rounded, weight: .heavy))
            Text(loc("TapPlusToFirst")).font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Color.maeusTextSecondary)
        }.frame(maxWidth: .infinity).foregroundStyle(Color.maeusForeground)
    }

    private var fabStack: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if settingsVM.voiceSettings.isReady {
                Button { editorVM.prepareForNew() } label: {
                    MaeusePlusIcon(color: Color(light: .maeusInk, dark: .white))
                }.buttonStyle(FABStyle(isPrimary: false)).accessibilityLabel(loc("AddExpense"))
                Button { voiceVM.open(provider: settingsVM.voiceSettings.provider) } label: {
                    MaeuseMicIcon(size: 24, color: .maeusInk)
                }.buttonStyle(FABStyle()).accessibilityLabel(loc("StartVoiceMode"))
            } else {
                Button { settingsVM.requestVoiceSetup() } label: {
                    MaeuseMicIcon(size: 24, color: .maeusForeground)
                }.buttonStyle(FABStyle(isPrimary: false)).accessibilityLabel(loc("VoiceChooseMode"))
                Button { editorVM.prepareForNew() } label: {
                    MaeusePlusIcon()
                }.buttonStyle(FABStyle()).accessibilityLabel(loc("AddExpense"))
            }
        }
    }
}
