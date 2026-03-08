import Foundation
import SwiftData

/// Manages the state of the add/edit expense sheet
@Observable
final class ExpenseEditorViewModel {
    var amountText: String = ""
    var description: String = ""
    var date: Date = Date()
    var splitMode: SplitMode = .percent
    var splitValueText: String = "50"
    var editingExpense: Expense? = nil
    var isPresented: Bool = false

    // MARK: - Computed

    var isEditing: Bool { editingExpense != nil }

    var sheetTitle: String {
        isEditing ? "Edit Expense" : "New Expense"
    }

    var parsedAmount: Double {
        let cleaned = amountText.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    var parsedSplitValue: Double {
        let cleaned = splitValueText.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    var splitResultText: String {
        let amount = parsedAmount
        let splitVal = parsedSplitValue
        switch splitMode {
        case .percent:
            let share = (amount * splitVal / 100).roundedMoney
            return "= \(share.euroFormatted)"
        case .fixed:
            let share = min(splitVal, amount).roundedMoney
            return "= \(share.euroFormatted)"
        }
    }

    var splitSuffix: String {
        splitMode == .percent ? "%" : "€"
    }

    var canSave: Bool {
        parsedAmount > 0
    }

    // MARK: - Actions

    func prepareForNew() {
        amountText = ""
        description = ""
        date = Date()
        splitMode = .percent
        splitValueText = "50"
        editingExpense = nil
        isPresented = true
    }

    func prepareForEdit(_ expense: Expense) {
        amountText = String(format: "%.2f", expense.amount)
        description = expense.desc
        date = expense.date
        splitMode = expense.splitMode
        splitValueText = expense.splitMode == .percent
            ? (expense.splitValue == expense.splitValue.rounded()
                ? String(Int(expense.splitValue))
                : String(format: "%.2f", expense.splitValue))
            : String(format: "%.2f", expense.splitValue)
        editingExpense = expense
        isPresented = true
    }

    func prepareFromVoiceDraft(_ draft: VoiceDraft) {
        amountText = draft.amount.map { String(format: "%.2f", $0) } ?? ""
        description = draft.description
        date = Expense.dateFromISO(draft.dateISO) ?? Date()
        splitMode = draft.partnerShareMode ?? .percent
        splitValueText = draft.partnerShareValue.map {
            $0 == $0.rounded() ? String(Int($0)) : String(format: "%.2f", $0)
        } ?? "50"
        editingExpense = nil
        isPresented = true
    }

    func selectPreset(_ value: Double) {
        splitMode = .percent
        splitValueText = value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    func setToday() {
        date = Date()
    }

    func save(context: ModelContext) {
        guard canSave else { return }

        if let existing = editingExpense {
            existing.amount = parsedAmount
            existing.desc = description
            existing.date = date
            existing.splitMode = splitMode
            existing.splitValue = parsedSplitValue
        } else {
            let expense = Expense(
                amount: parsedAmount,
                desc: description,
                date: date,
                splitMode: splitMode,
                splitValue: parsedSplitValue
            )
            context.insert(expense)
        }

        try? context.save()
        isPresented = false
    }

    func delete(context: ModelContext) {
        guard let expense = editingExpense else { return }
        context.delete(expense)
        try? context.save()
        isPresented = false
    }
}
