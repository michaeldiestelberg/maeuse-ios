import SwiftUI

struct MainExpenseView: View {
    @Bindable var listVM: ExpenseListViewModel
    @Bindable var editorVM: ExpenseEditorViewModel
    @Bindable var voiceVM: VoiceModeViewModel
    @Bindable var settingsVM: SettingsViewModel
    let expenses: [Expense]
    let onShowWelcomeGuide: () -> Void

    @State private var direction: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filtered: [Expense] { listVM.filteredExpenses(from: expenses) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PrismBackground()
            VStack(spacing: 0) {
                header.padding(.horizontal, 22).padding(.top, 12)
                ZStack {
                    monthContent
                        .id("\(listVM.currentYear)-\(listVM.currentMonth)")
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .offset(x: direction * 14).combined(with: .opacity),
                            removal: .opacity))
                }
            }
            fabStack.padding(.trailing, 22).padding(.bottom, 30)
        }
        .fontDesign(.rounded)
        .sheet(isPresented: $editorVM.isPresented) { ExpenseEditorSheet(viewModel: editorVM) }
        .fullScreenCover(isPresented: $voiceVM.isPresented) { VoiceSheet(viewModel: voiceVM) }
        .sheet(isPresented: $settingsVM.isPresented) {
            SettingsSheet(
                viewModel: settingsVM,
                expenses: expenses,
                onShowWelcomeGuide: onShowWelcomeGuide
            )
        }
    }

    private var header: some View {
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
            Button { settingsVM.isPresented = true } label: {
                MaeuseSettingsIcon().frame(width: 38, height: 38)
            }
            .buttonStyle(StampedButtonStyle(fill: .maeusSurface, foreground: .maeusForeground, cornerRadius: 19, borderColor: .maeusCardBorder, shadow: 3, shadowColor: Color(hex: "E8A800")))
            .accessibilityLabel(loc("Settings"))
        }
    }

    private var monthContent: some View {
        VStack(spacing: 0) {
            summaryCard.padding(.horizontal, 22).padding(.top, 20)
            ScrollView {
                LazyVStack(spacing: 12) {
                    if filtered.isEmpty { emptyState.padding(.top, 44) }
                    else {
                        ForEach(filtered, id: \.id) { expense in
                            ExpenseRow(expense: expense, listVM: listVM)
                                .contentShape(Rectangle()).onTapGesture { editorVM.prepareForEdit(expense) }
                                .transition(.scale(scale: 0.82).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 120)
            }
        }
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
                        .font(.system(size: 42, weight: .heavy, design: .rounded)).tracking(-1.5).monospacedDigit()
                    HStack(spacing: 6) {
                        Text(loc("MausOwesYou")).font(.system(size: 14, weight: .bold, design: .rounded))
                        Text(listVM.partnerTotal(for: filtered).euroFormatted)
                            .font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Color.maeusCheese).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.maeusInk, in: RoundedRectangle(cornerRadius: 8))
                            .contentTransition(.numericText())
                    }
                }
            }
            .foregroundStyle(Color.maeusInk).padding(.horizontal, 22).padding(.vertical, 20)
            .overlay {
                GeometryReader { geometry in
                    FloatingCheeseHole(size: 34, duration: 7, stroke: .maeusInk)
                        .position(x: geometry.size.width - 53, y: 5)
                    FloatingCheeseHole(size: 14, duration: 8, delay: 2, stroke: .maeusInk)
                        .position(x: geometry.size.width - 103, y: 33)
                    FloatingCheeseHole(size: 22, duration: 9, delay: 1, stroke: .maeusInk)
                        .position(x: geometry.size.width - 3, y: geometry.size.height - 25)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private func monthButton(direction newDirection: CGFloat) -> some View {
        Button {
            direction = newDirection
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.35)) {
                newDirection < 0 ? listVM.previousMonth() : listVM.nextMonth()
            }
        } label: {
            MaeuseChevronIcon(pointsRight: newDirection > 0).frame(width: 28, height: 28)
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
                    MaeusePlusIcon()
                }.buttonStyle(FABStyle(isPrimary: false)).accessibilityLabel(loc("AddExpense"))
                Button { voiceVM.open() } label: {
                    MaeuseMicIcon(size: 24, color: .maeusInk)
                }.buttonStyle(FABStyle()).accessibilityLabel(loc("StartVoiceMode"))
            } else {
                Button { editorVM.prepareForNew() } label: {
                    MaeusePlusIcon()
                }.buttonStyle(FABStyle()).accessibilityLabel(loc("AddExpense"))
            }
        }
    }
}
