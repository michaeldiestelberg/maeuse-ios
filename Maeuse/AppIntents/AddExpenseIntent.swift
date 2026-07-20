import AppIntents

/// Opens Mäuse into the requested expense-capture destination.
@available(iOS 18.0, *)
struct CaptureExpenseIntent: OpenIntent {
    static let title: LocalizedStringResource = "Mäuse"
    static let isDiscoverable: Bool = true

    @Parameter(title: "Mäuse")
    var target: CaptureLaunchDestination

    init() {
        target = .addExpense
    }

    init(target: CaptureLaunchDestination) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureLaunchRouter.setPending(target)
        return .result()
    }
}
