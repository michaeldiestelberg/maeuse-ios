import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen / Control Center / Action button control for Voice Mode capture.
struct DictateExpenseControl: ControlWidget {
    static let kind = "com.michaeldiestelberg.maeuse.controls.dictateExpense"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: DictateExpenseIntent()) {
                Label(LocalizedStringResource("ControlDictateExpenseTitle"), image: "maeuse.mouse.mic")
            }
        }
        .displayName(LocalizedStringResource("ControlDictateExpenseTitle"))
        .description(LocalizedStringResource("ControlDictateExpenseDescription"))
    }
}
