import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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

        // Delete all existing
        try context.delete(model: Expense.self)

        // Insert new
        for expense in expenses {
            context.insert(expense)
        }

        try context.save()
    }
}
