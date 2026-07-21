import WidgetKit
import SwiftUI

@main
struct MaeuseControlsBundle: WidgetBundle {
    var body: some Widget {
        AddExpenseControl()
        DictateExpenseControl()
        AddExpenseWidget()
        DictateExpenseWidget()
    }
}
