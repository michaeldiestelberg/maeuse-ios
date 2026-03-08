import Foundation
import SwiftData
import UIKit

/// Handles export/import of expense data as JSON backup files
struct BackupService {

    // MARK: - Export

    static func exportBackup(expenses: [Expense]) throws -> Data {
        let backups = expenses.map { ExpenseBackup(from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backups)
    }

    static func exportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "maeuse-backup-\(formatter.string(from: Date())).json"
    }

    // MARK: - Import

    static func parseBackup(data: Data) throws -> [ExpenseBackup] {
        let decoder = JSONDecoder()
        return try decoder.decode([ExpenseBackup].self, from: data)
    }

    /// Replace all expenses in the model context with imported ones
    static func replaceAllExpenses(
        in context: ModelContext,
        with backups: [ExpenseBackup]
    ) throws {
        // Delete all existing
        try context.delete(model: Expense.self)

        // Insert new
        for backup in backups {
            if let expense = backup.toExpense() {
                context.insert(expense)
            }
        }

        try context.save()
    }
}
