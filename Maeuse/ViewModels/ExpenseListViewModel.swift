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
        let monthNames = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        guard currentMonth >= 1 && currentMonth <= 12 else { return "" }
        return "\(monthNames[currentMonth - 1]) \(currentYear)"
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
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }

    func formatSplit(_ expense: Expense) -> String {
        switch expense.splitMode {
        case .percent:
            let pct = expense.splitValue
            if pct == pct.rounded() {
                return "\(Int(pct)) %"
            }
            return String(format: "%.1f %%", pct)
        case .fixed:
            return expense.splitValue.euroFormatted
        }
    }
}
