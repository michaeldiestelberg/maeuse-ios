import Foundation
import SwiftData

/// Split mode: percentage-based or fixed euro amount
enum SplitMode: String, Codable {
    case percent
    case fixed
}

/// Persistent expense model backed by SwiftData (replaces IndexedDB)
@Model
final class Expense {
    @Attribute(.unique) var id: String
    var amount: Double
    var desc: String
    var date: Date
    var splitMode: SplitMode
    var splitValue: Double
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        amount: Double,
        desc: String,
        date: Date,
        splitMode: SplitMode = .percent,
        splitValue: Double = 50,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.desc = desc
        self.date = date
        self.splitMode = splitMode
        self.splitValue = splitValue
        self.createdAt = createdAt
    }

    /// Calculate the partner's share based on split mode
    var partnerShare: Double {
        switch splitMode {
        case .percent:
            return (amount * splitValue / 100).roundedMoney
        case .fixed:
            return min(splitValue, amount).roundedMoney
        }
    }

    /// Date as ISO string (YYYY-MM-DD)
    var dateISO: String {
        Self.isoFormatter.string(from: date)
    }

    /// Year and month components
    var yearMonth: (year: Int, month: Int) {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return (components.year ?? 2026, components.month ?? 1)
    }

    // MARK: - Formatters

    static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func dateFromISO(_ string: String) -> Date? {
        isoFormatter.date(from: string)
    }
}

// MARK: - Backup Codable Wrapper

struct ExpenseBackup: Codable {
    let id: String
    let amount: Double
    let description: String
    let date: String
    let splitMode: String
    let splitValue: Double
    let createdAt: String?

    init(from expense: Expense) {
        self.id = expense.id
        self.amount = expense.amount
        self.description = expense.desc
        self.date = expense.dateISO
        self.splitMode = expense.splitMode.rawValue
        self.splitValue = expense.splitValue
        self.createdAt = ISO8601DateFormatter().string(from: expense.createdAt)
    }

    func toExpense() -> Expense? {
        guard let expenseDate = Expense.dateFromISO(date) else { return nil }
        let mode = SplitMode(rawValue: splitMode) ?? .percent
        let created: Date
        if let createdStr = createdAt {
            created = ISO8601DateFormatter().date(from: createdStr) ?? Date()
        } else {
            created = Date()
        }
        return Expense(
            id: id,
            amount: amount,
            desc: description,
            date: expenseDate,
            splitMode: mode,
            splitValue: splitValue,
            createdAt: created
        )
    }
}

// MARK: - Money Rounding

extension Double {
    var roundedMoney: Double {
        (self * 100).rounded() / 100
    }

    var euroFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US")
        return (formatter.string(from: NSNumber(value: self)) ?? "0.00") + " €"
    }
}
