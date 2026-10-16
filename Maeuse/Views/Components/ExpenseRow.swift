import SwiftUI

struct ExpenseRow: View {
    let expense: Expense
    let listVM: ExpenseListViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CheeseCard(cornerRadius: 18, borderWidth: 2, shadow: 3) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: -1) {
                    Text(dayString).font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text(monthString).font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(1).foregroundStyle(Color.maeusTextSecondary)
                }
                .frame(width: 40, height: 40)
                .background(Color.maeusInputBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.maeusCardBorder, lineWidth: 2))

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(expense.desc.isEmpty ? loc("Expense") : expense.desc)
                            .font(.system(.body, design: .rounded, weight: .heavy)).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        Text(listVM.formatSplit(expense))
                            .font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Color.maeusTextSecondary)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                        Text(expense.amount.euroFormatted).font(.system(.body, design: .rounded, weight: .heavy)).monospacedDigit()
                        Text(expense.partnerShare.euroFormatted).font(.system(.caption, design: .rounded, weight: .heavy)).monospacedDigit().foregroundStyle(Color.maeusPrimaryHover)
                    }
                }
            }.foregroundStyle(Color.maeusForeground).padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private var dayString: String { expense.date.formatted(.dateTime.day()) }
    private var monthString: String {
        let f = DateFormatter(); f.dateFormat = "MMM"; f.locale = LanguageManager.shared.activeLocale
        return f.string(from: expense.date).uppercased()
    }
}
