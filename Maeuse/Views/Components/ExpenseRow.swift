import SwiftUI

/// A single expense row in the list
struct ExpenseRow: View {
    let expense: Expense
    let listVM: ExpenseListViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Date badge
            VStack(spacing: 0) {
                Text(dayString)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.maeusText)
                Text(monthString)
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(Color.maeusTextTertiary)
                    .textCase(.uppercase)
            }
            .frame(width: 36)

            // Description + split
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.desc.isEmpty ? "Expense" : expense.desc)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.maeusText)
                    .lineLimit(1)

                Text(listVM.formatSplit(expense))
                    .font(.caption)
                    .foregroundStyle(Color.maeusTextTertiary)
            }

            Spacer()

            // Amounts
            VStack(alignment: .trailing, spacing: 2) {
                Text(expense.amount.euroFormatted)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.maeusText)

                Text(expense.partnerShare.euroFormatted)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.maeusPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: expense.date)
    }

    private var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: expense.date)
    }
}
