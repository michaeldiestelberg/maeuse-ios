import AppIntents

/// Opens Mäuse into Voice Mode (or Settings when Voice Mode is not ready).
@available(iOS 18.0, *)
struct DictateExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "ControlDictateExpenseTitle"
    static let description = IntentDescription("ControlDictateExpenseDescription")
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureLaunchRouter.setPending(.dictateExpense)
        return .result()
    }
}
