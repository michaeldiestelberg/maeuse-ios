import SwiftUI

struct ExpenseRow: View {
    let expense: Expense
    let listVM: ExpenseListViewModel

    var body: some View {
        CheeseCard(cornerRadius: 18, borderWidth: 2, shadow: 3) {
            HStack(spacing: 12) {
                VStack(spacing: -1) {
                    Text(dayString).font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text(monthString).font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(1).foregroundStyle(Color.maeusTextSecondary)
                }
                .frame(width: 40, height: 40)
                .background(Color.maeusInputBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.maeusCardBorder, lineWidth: 2))

                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.desc.isEmpty ? loc("Expense") : expense.desc)
                        .font(.system(size: 15, weight: .heavy, design: .rounded)).lineLimit(1)
                    Text(listVM.formatSplit(expense))
                        .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Color.maeusTextSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(expense.amount.euroFormatted).font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text(expense.partnerShare.euroFormatted).font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Color.maeusPrimaryHover)
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
