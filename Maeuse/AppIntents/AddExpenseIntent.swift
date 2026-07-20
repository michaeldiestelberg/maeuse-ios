import AppIntents

/// Opens Mäuse into the manual expense editor.
@available(iOS 18.0, *)
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "ControlAddExpenseTitle"
    static let description = IntentDescription("ControlAddExpenseDescription")
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureLaunchRouter.setPending(.addExpense)
        return .result()
    }
}
