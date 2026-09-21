import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

/// An immutable JSON export. Transferable supports the system exporter on iOS 17+
/// without the deprecated FileDocument lifecycle or a separate legacy path.
struct BackupDocument: Transferable, Sendable {
    let data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { document in
            document.data
        }
    }
}

/// Handles export/import of expense data as JSON backup files
struct BackupService {

    enum BackupError: LocalizedError {
        case invalidExpense
        case duplicateExpenseIDs

        var errorDescription: String? {
            switch self {
            case .invalidExpense: "The backup contains an invalid expense."
            case .duplicateExpenseIDs: "The backup contains duplicate expense IDs."
            }
        }
    }

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
        let backups = try decoder.decode([ExpenseBackup].self, from: data)
        guard backups.allSatisfy({ $0.toExpense() != nil }) else {
            throw BackupError.invalidExpense
        }
        guard Set(backups.map(\.id)).count == backups.count else {
            throw BackupError.duplicateExpenseIDs
        }
        return backups
    }

    /// Replace all expenses in the model context with imported ones
    static func replaceAllExpenses(
        in context: ModelContext,
        with backups: [ExpenseBackup]
    ) throws {
        guard Set(backups.map(\.id)).count == backups.count else { throw BackupError.duplicateExpenseIDs }
        let expenses = try backups.map { backup -> Expense in
            guard let expense = backup.toExpense() else { throw BackupError.invalidExpense }
            return expense
        }

        // SwiftData can leave a failed save's inserted/deleted objects registered
        // even after rollback. Never perform a destructive restore in the UI context.
        let replacement = ModelContext(context.container)
        replacement.autosaveEnabled = false
        for expense in try replacement.fetch(FetchDescriptor<Expense>()) {
            replacement.delete(expense)
        }
        for expense in expenses { replacement.insert(expense) }
        try replacement.save()
    }
}
