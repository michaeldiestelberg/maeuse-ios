import SwiftUI
import SwiftData

struct ExpenseEditorSheet: View {
    @Bindable var viewModel: ExpenseEditorViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showDatePicker = false
    @State private var showPersistenceError = false
    @State private var persistenceErrorMessage = ""
    @FocusState private var noteFocused: Bool

    private var decimalSeparator: String {
        LanguageManager.shared.activeLanguageCode == "de" ? "," : "."
    }

    private var keys: [String] {
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", decimalSeparator, "0", "⌫"]
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.maeusTextTertiary.opacity(0.45)).frame(width: 40, height: 5).padding(.top, 10)
            topBar.padding(.horizontal, 22).padding(.top, 8)
            hero.padding(.top, 14)
            noteField.padding(.horizontal, 22).padding(.top, 16)
            datePicker.padding(.horizontal, 22).padding(.top, 12)
            details.padding(.horizontal, 22).padding(.top, 12)
            if viewModel.isEditing {
                deleteAction.padding(.horizontal, 22).padding(.top, 12)
            }
            Spacer(minLength: 10)
            keypad.padding(.horizontal, 22).padding(.bottom, 24)
        }
        .fontDesign(.rounded).background(Color.maeusBackground.ignoresSafeArea())
        .presentationDetents([.large]).presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
        .confirmationDialog(loc("DeleteConfirmationTitle"), isPresented: $showDeleteConfirmation) {
            Button(loc("DeleteExpense"), role: .destructive) { deleteExpense() }
            Button(loc("Cancel"), role: .cancel) { }
        }
        .alert(loc("PersistenceErrorTitle"), isPresented: $showPersistenceError) {
            Button(loc("OK"), role: .cancel) { }
        } message: {
            Text(persistenceErrorMessage)
        }
        .sheet(isPresented: $showDatePicker) {
            themedCalendar
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(30)
        }
    }

    private var topBar: some View {
        HStack {
            circleButton(isCheck: false, fill: .maeusSurface) { dismiss() }
            Spacer(); Text(viewModel.sheetTitle).font(.system(.headline, design: .rounded, weight: .heavy)); Spacer()
            circleButton(isCheck: true, fill: .maeusCheese) { saveExpense() }
                .opacity(viewModel.canSave ? 1 : 0.4).disabled(!viewModel.canSave)
        }.foregroundStyle(Color.maeusForeground)
    }

    private func circleButton(isCheck: Bool, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group { if isCheck { MaeuseCheckIcon() } else { MaeuseCloseIcon() } }.frame(width: 38, height: 38)
        }
            .buttonStyle(StampedButtonStyle(fill: fill, foreground: fill == .maeusCheese ? .maeusInk : .maeusForeground,
                                            cornerRadius: 19, borderColor: fill == .maeusCheese ? .maeusInk : .maeusCardBorder, shadow: fill == .maeusCheese ? 2.5 : 0))
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("€").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Color.maeusTextSecondary)
            Text(viewModel.amountText.isEmpty ? "0.00" : viewModel.amountText)
                .font(.system(size: 48, weight: .heavy, design: .rounded)).tracking(-2).monospacedDigit()
                .foregroundStyle(viewModel.amountText.isEmpty ? Color.maeusTextTertiary : Color.maeusForeground)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.maeusCheese).frame(height: 4).offset(y: 4) }
        }
    }

    private var noteField: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 13, weight: .heavy))
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.maeusInk)
                .background(Color.maeusCheese, in: Circle())
                .overlay(Circle().stroke(Color.maeusInk, lineWidth: 1.5))
                .accessibilityHidden(true)
            TextField(loc("AddNote"), text: $viewModel.description)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.maeusForeground)
                .textFieldStyle(.plain)
                .focused($noteFocused)
                .submitLabel(.done)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background { fieldBackground }
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .onTapGesture { noteFocused = true }
    }

    private var fieldBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        return ZStack {
            shape.fill(Color(light: Color.maeusInk.opacity(0.12), dark: Color.black.opacity(0.5)))
                .offset(y: 3)
            shape.fill(Color.maeusSurface)
            shape.stroke(Color.maeusCardBorder, lineWidth: 2)
        }
    }

    private var details: some View {
        CheeseCard(cornerRadius: 22, shadow: 4) {
            VStack(spacing: 11) {
                HStack {
                    share(title: loc("You"), value: viewModel.splitMode == .fixed ? "rest" : "\(viewModel.userPercent)%", amount: viewModel.userShareAmount.euroFormatted, accent: false)
                    Spacer()
                    share(title: loc("Partner"), value: viewModel.splitMode == .fixed ? viewModel.parsedSplitValue.euroFormatted : "\(viewModel.partnerPercent)%", amount: viewModel.partnerShareAmount.euroFormatted, accent: true)
                }
                GeometryReader { geo in
                    let x = geo.size.width * (1 - viewModel.partnerFraction)
                    ZStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            Color.maeusInputBackground.frame(width: x); Color.maeusCheese
                        }.clipShape(Capsule()).overlay(Capsule().stroke(Color.maeusCardBorder, lineWidth: 2.5)).frame(height: 20)
                        Capsule().fill(Color.maeusForeground).frame(width: 9, height: 30).offset(x: x - 4.5)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { updateSplit(at: $0.location.x, width: geo.size.width) }
                    )
                    .accessibilityElement()
                    .accessibilityLabel(loc("Partner"))
                    .accessibilityValue("\(viewModel.partnerPercent)%")
                    .accessibilityAdjustableAction { direction in
                        let change = direction == .increment ? 5 : -5
                        setPartnerPercent(viewModel.partnerPercent + change)
                    }
                }.frame(height: 30)
            }.padding(.horizontal, 18).padding(.vertical, 14)
        }
    }

    private var deleteAction: some View {
        Button(role: .destructive) { showDeleteConfirmation = true } label: {
            Label {
                Text(loc("DeleteExpense"))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            } icon: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(
            StampedButtonStyle(
                fill: .maeusSurface,
                foreground: .maeusDestructive,
                cornerRadius: 15,
                borderColor: .maeusDestructive,
                shadow: 3,
                shadowColor: .maeusDestructive.opacity(0.22)
            )
        )
        .accessibilityHint(loc("DeleteConfirmationTitle"))
    }

    private var datePicker: some View {
        Button { showDatePicker = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .heavy))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.maeusInk)
                    .background(Color.maeusCheese, in: Circle())
                    .overlay(Circle().stroke(Color.maeusInk, lineWidth: 1.5))
                Text(loc("Date").uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(Color.maeusTextSecondary)
                Spacer()
                Text(viewModel.dateDisplay)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.maeusForeground)
                MaeuseChevronIcon(pointsRight: true).frame(width: 18, height: 18)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background { fieldBackground }
        .accessibilityLabel(loc("Date"))
        .accessibilityValue(viewModel.dateDisplay)
    }

    private var themedCalendar: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.maeusTextTertiary.opacity(0.45))
                .frame(width: 40, height: 5).padding(.top, 10)
            HStack {
                Text(loc("Date").localizedCapitalized)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.maeusForeground)
                Spacer()
                Button { showDatePicker = false } label: {
                    Text(loc("Done"))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                    .buttonStyle(StampedButtonStyle(fill: .maeusCheese, foreground: .maeusInk,
                                                    cornerRadius: 18, borderColor: .maeusInk, shadow: 2.5))
            }
            .padding(.horizontal, 22).padding(.top, 8)
            DatePicker("", selection: $viewModel.date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.graphical)
                .tint(Color.maeusPrimary)
                .padding(.horizontal, 14).padding(.top, 4)
        }
        .fontDesign(.rounded)
        .background(Color.maeusBackground.ignoresSafeArea())
    }

    private func share(title: String, value: String, amount: String, accent: Bool) -> some View {
        VStack(alignment: accent ? .trailing : .leading, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.5)
            Text(value).font(.system(size: 19, weight: .heavy, design: .rounded))
            Text(amount).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Color.maeusTextSecondary)
        }.foregroundStyle(accent ? Color.maeusPrimaryHover : Color.maeusForeground)
    }

    private func updateSplit(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        viewModel.setPartnerFraction(1 - min(max(x / width, 0), 1))
    }

    private func setPartnerPercent(_ percent: Int) {
        viewModel.setPartnerFraction(Double(min(max(percent, 0), 100)) / 100)
    }

    private var keypad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
            ForEach(keys, id: \.self) { key in
                Button { type(key) } label: { Text(key).font(.system(size: 21, weight: .heavy, design: .rounded)).frame(maxWidth: .infinity).frame(height: 50) }
                    .buttonStyle(StampedButtonStyle(fill: key == "0" || key.first?.isNumber == true ? .maeusSurface : .maeusBackground,
                                                    foreground: .maeusForeground, cornerRadius: 14, borderColor: key == "0" || key.first?.isNumber == true ? .maeusCardBorder : .maeusSoftBorder, shadow: 0))
            }
        }
    }

    private func type(_ key: String) {
        if key == "⌫" { if !viewModel.amountText.isEmpty { viewModel.amountText.removeLast() }; return }
        let isDecimalKey = key == "." || key == ","
        let existingDecimal = viewModel.amountText.firstIndex { $0 == "." || $0 == "," }
        if isDecimalKey && existingDecimal != nil { return }
        if let decimal = existingDecimal,
           viewModel.amountText.distance(from: decimal, to: viewModel.amountText.endIndex) > 2 {
            return
        }
        let digitCount = viewModel.amountText.filter(\.isNumber).count
        if digitCount >= 6 { return }
        viewModel.amountText += key
    }

    private func saveExpense() {
        do {
            try viewModel.save(context: modelContext)
        } catch {
            persistenceErrorMessage = loc("SaveExpenseFailed", error.localizedDescription)
            showPersistenceError = true
        }
    }

    private func deleteExpense() {
        do {
            try viewModel.delete(context: modelContext)
        } catch {
            persistenceErrorMessage = loc("DeleteExpenseFailed", error.localizedDescription)
            showPersistenceError = true
        }
    }
}
