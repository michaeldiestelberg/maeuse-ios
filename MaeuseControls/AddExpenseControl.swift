import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen / Control Center / Action button control for manual expense entry.
struct AddExpenseControl: ControlWidget {
    static let kind = "com.michaeldiestelberg.maeuse.controls.addExpense"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AddExpenseIntent()) {
                Label(LocalizedStringResource("ControlAddExpenseTitle"), image: "maeuse.mouse.plus")
            }
        }
        .displayName(LocalizedStringResource("ControlAddExpenseTitle"))
        .description(LocalizedStringResource("ControlAddExpenseDescription"))
    }
}
