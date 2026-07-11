import Foundation
import SwiftData
import Observation

/// Manages the current month view, summary calculations, and expense CRUD
@Observable
final class ExpenseListViewModel {
    var currentYear: Int
    var currentMonth: Int

    init() {
        let now = Date()
        let components = Calendar.current.dateComponents([.year, .month], from: now)
        self.currentYear = components.year ?? 2026
        self.currentMonth = components.month ?? 1
    }

    // MARK: - Month Navigation

    var monthLabel: String {
        var components = DateComponents()
        components.year = currentYear
        components.month = currentMonth
        components.day = 1
        guard let date = Calendar.current.date(from: components) else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = LanguageManager.shared.activeLocale
        return formatter.string(from: date)
    }


    func previousMonth() {
        if currentMonth == 1 {
            currentMonth = 12
            currentYear -= 1
        } else {
            currentMonth -= 1
        }
    }

    func nextMonth() {
        if currentMonth == 12 {
            currentMonth = 1
            currentYear += 1
        } else {
            currentMonth += 1
        }
    }

    // MARK: - Filtering & Summary

    func filteredExpenses(from allExpenses: [Expense]) -> [Expense] {
        allExpenses
            .filter { expense in
                let ym = expense.yearMonth
                return ym.year == currentYear && ym.month == currentMonth
            }
            .sorted { $0.date > $1.date }
    }

    func totalAmount(for expenses: [Expense]) -> Double {
        expenses.reduce(0) { $0 + $1.amount }.roundedMoney
    }

    func partnerTotal(for expenses: [Expense]) -> Double {
        expenses.reduce(0) { $0 + $1.partnerShare }.roundedMoney
    }

    // MARK: - Date Formatting

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if LanguageManager.shared.activeLanguageCode == "de" {
            formatter.dateFormat = "d. MMM"
        } else {
            formatter.dateFormat = "d MMM"
        }
        formatter.locale = LanguageManager.shared.activeLocale
        return formatter.string(from: date)
    }


    func formatSplit(_ expense: Expense) -> String {
        switch expense.splitMode {
        case .percent:
            let pct = expense.splitValue
            if pct == pct.rounded() {
                return loc("PercentSplit", 100 - Int(pct), Int(pct))
            }
            return loc("PercentSplitDecimal", 100 - pct, pct)
        case .fixed:
            return loc("FixedSplit", expense.splitValue.euroFormatted)
        }
    }
}
