import SwiftUI
import SwiftData

/// Bottom sheet for adding or editing an expense
struct ExpenseEditorSheet: View {
    @Bindable var viewModel: ExpenseEditorViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let presetValues: [Double] = [50, 30, 70, 100]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Amount input
                    amountSection

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.maeusTextSecondary)
                        TextField("e.g. Groceries, Dinner…", text: $viewModel.description)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .padding(12)
                            .background(Color.maeusInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Date
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.maeusTextSecondary)
                        HStack(spacing: 12) {
                            DatePicker("", selection: $viewModel.date, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)

                            Button("Today") {
                                viewModel.setToday()
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.maeusPrimaryLight)
                            .foregroundStyle(Color.maeusPrimary)
                            .clipShape(Capsule())
                        }
                    }

                    // Split section
                    splitSection

                    // Delete button (edit mode only)
                    if viewModel.isEditing {
                        Button(role: .destructive) {
                            viewModel.delete(context: modelContext)
                            dismiss()
                        } label: {
                            Text("Delete Expense")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.maeusBackground)
            .navigationTitle(viewModel.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.isPresented = false
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.save(context: modelContext)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canSave)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Amount Section

    private var amountSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("€")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.maeusTextTertiary)

            TextField("0.00", text: $viewModel.amountText)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .foregroundStyle(Color.maeusText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Split Section

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.maeusTextSecondary)

            // Mode toggle
            HStack(spacing: 0) {
                splitModeButton("Percentage", mode: .percent)
                splitModeButton("Fixed Amount", mode: .fixed)
            }
            .background(Color.maeusInputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Preset chips (percent mode only)
            if viewModel.splitMode == .percent {
                HStack(spacing: 8) {
                    ForEach(presetValues, id: \.self) { value in
                        Button("\(Int(value)) %") {
                            viewModel.selectPreset(value)
                        }
                        .buttonStyle(ChipStyle(isSelected: viewModel.parsedSplitValue == value))
                    }
                }
            }

            // Split value input + result
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    TextField("", text: $viewModel.splitValueText)
                        .font(.body.monospacedDigit())
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)

                    Text(viewModel.splitSuffix)
                        .font(.body)
                        .foregroundStyle(Color.maeusTextTertiary)
                }
                .padding(10)
                .background(Color.maeusInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(viewModel.splitResultText)
                    .font(.subheadline)
                    .foregroundStyle(Color.maeusTextSecondary)

                Spacer()
            }
        }
    }

    private func splitModeButton(_ title: String, mode: SplitMode) -> some View {
        Button {
            viewModel.splitMode = mode
            if mode == .percent {
                viewModel.splitValueText = "50"
            } else {
                viewModel.splitValueText = ""
            }
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(viewModel.splitMode == mode ? Color.maeusPrimary.opacity(0.12) : Color.clear)
                .foregroundStyle(viewModel.splitMode == mode ? Color.maeusPrimary : Color.maeusTextSecondary)
        }
    }
}
