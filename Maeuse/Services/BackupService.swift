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
        let expenses = try backups.map { backup -> Expense in
            guard let expense = backup.toExpense() else { throw BackupError.invalidExpense }
            return expense
        }

        do {
            // Stage replacement in one context save so failure can restore the
            // original ledger, including when imported IDs match existing rows.
            for expense in try context.fetch(FetchDescriptor<Expense>()) {
                context.delete(expense)
            }
            for expense in expenses {
                context.insert(expense)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
