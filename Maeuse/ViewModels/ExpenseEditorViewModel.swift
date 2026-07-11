import Foundation
import SwiftData

/// Manages the state of the add/edit expense sheet.
///
/// Splits are always expressed as a partner percentage (5% steps via the
/// visual slider). The `SplitMode` enum still exists on the data model for
/// backwards compatibility with any expenses stored under `.fixed`, and we
/// migrate them to a percentage on edit.
@Observable
final class ExpenseEditorViewModel {
    var amountText: String = ""
    var description: String = ""
    var date: Date = Date()
    var splitValueText: String = "50"
    var splitMode: SplitMode = .percent
    var editingExpense: Expense? = nil
    var isPresented: Bool = false

    // MARK: - Computed

    var isEditing: Bool { editingExpense != nil }

    var sheetTitle: String {
        isEditing ? loc("EditExpense") : loc("NewExpense")
    }


    var parsedAmount: Double {
        let cleaned = amountText.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    var parsedSplitValue: Double {
        let cleaned = splitValueText.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    var partnerShareAmount: Double {
        switch splitMode {
        case .percent: (parsedAmount * parsedSplitValue / 100).roundedMoney
        case .fixed: min(parsedSplitValue, parsedAmount).roundedMoney
        }
    }

    var userShareAmount: Double {
        max(parsedAmount - partnerShareAmount, 0).roundedMoney
    }

    /// Partner's share as a fraction of the total (0...1). Used by the visual
    /// split bar to position the divider. Defaults to 0.5 when the total
    /// amount is zero so the bar shows centered on a fresh expense.
    var partnerFraction: Double {
        guard parsedAmount > 0 else { return 0.5 }
        let fraction = splitMode == .fixed ? parsedSplitValue / parsedAmount : parsedSplitValue / 100
        return min(max(fraction, 0), 1)
    }

    var partnerPercent: Int {
        min(max(Int((partnerFraction * 100).rounded()), 0), 100)
    }

    var userPercent: Int {
        100 - partnerPercent
    }

    /// Natural-language label for the date. "Today" 99% of the time on a fresh
    /// expense, so we let it speak for itself instead of showing a redundant date pill.
    var dateDisplay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return loc("Today") }
        if calendar.isDateInYesterday(date) { return loc("Yesterday") }
        if calendar.isDateInTomorrow(date) { return loc("Tomorrow") }

        let formatter = DateFormatter()
        if LanguageManager.shared.activeLanguageCode == "de" {
            formatter.dateFormat = "EEE, d. MMM"
        } else {
            formatter.dateFormat = "EEE, d MMM"
        }
        formatter.locale = LanguageManager.shared.activeLocale
        return formatter.string(from: date)
    }


    var canSave: Bool {
        parsedAmount > 0
    }

    // MARK: - Actions

    /// Update the partner's share from the visual slider position (0 = no
    /// partner contribution, 1 = partner pays everything). Snaps to 5%
    /// increments so the slider feels decisive rather than fiddly.
    func setPartnerFraction(_ fraction: Double) {
        splitMode = .percent
        let clamped = min(max(fraction, 0), 1)
        let pct = clamped * 100
        let snapped = (pct / 5).rounded() * 5
        splitValueText = "\(Int(snapped))"
    }

    /// Reformat the amount field into locale-aware two-decimal form (e.g. "5"
    /// → "5,00" in de_DE, "5.00" in en_US). Called when the amount field
    /// loses focus, so the visible text always settles into a tidy display.
    func formatAmountText() {
        let amount = parsedAmount
        guard amount > 0 else { return }
        amountText = formattedAmount(amount)
    }

    func prepareForNew() {
        amountText = ""
        description = ""
        date = Date()
        splitValueText = "50"
        splitMode = .percent
        editingExpense = nil
        isPresented = true
    }

    func prepareForEdit(_ expense: Expense) {
        amountText = formattedAmount(expense.amount)
        description = expense.desc
        date = expense.date

        splitMode = expense.splitMode
        splitValueText = expense.splitValue == expense.splitValue.rounded()
            ? String(Int(expense.splitValue)) : String(format: "%.2f", expense.splitValue)

        editingExpense = expense
        isPresented = true
    }

    func save(context: ModelContext) throws {
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

        do {
            try context.save()
            isPresented = false
        } catch {
            context.rollback()
            throw error
        }
    }

    func delete(context: ModelContext) throws {
        guard let expense = editingExpense else { return }
        context.delete(expense)

        do {
            try context.save()
            isPresented = false
        } catch {
            context.rollback()
            throw error
        }
    }

    private func formattedAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = LanguageManager.shared.activeLocale
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}
