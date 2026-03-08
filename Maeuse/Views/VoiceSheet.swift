import SwiftUI

/// Bottom sheet for voice-based expense entry
struct VoiceSheet: View {
    @Bindable var viewModel: VoiceModeViewModel
    @Bindable var editorVM: ExpenseEditorViewModel
    let apiKey: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Capture Zone (idle/recording/processing)
                if viewModel.phase != .review {
                    captureZone
                }

                // Review State
                if viewModel.phase == .review {
                    reviewContent
                }

                // Error State
                if viewModel.phase == .error {
                    errorContent
                }

                Spacer()

                // Footer Actions
                if viewModel.phase == .review || viewModel.phase == .error {
                    footerActions
                }
            }
            .padding(20)
            .background(Color.maeusBackground)
            .navigationTitle("Voice Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.close()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.showDoneButton {
                        Button("Done") {
                            saveVoiceDraft()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(viewModel.phase == .recording || viewModel.phase == .processing)
    }

    // MARK: - Capture Zone

    private var captureZone: some View {
        VStack(spacing: 16) {
            // Mic button
            Button {
                viewModel.toggleRecording(apiKey: apiKey)
            } label: {
                ZStack {
                    // Pulsing glow when recording
                    if viewModel.phase == .recording {
                        Circle()
                            .fill(Color.maeusPrimary.opacity(0.15))
                            .frame(width: 120, height: 120)
                            .scaleEffect(pulseScale)
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: viewModel.phase
                            )
                    }

                    Circle()
                        .fill(
                            viewModel.phase == .recording
                                ? Color.maeusDestructive.opacity(0.9)
                                : Color.maeusPrimary
                        )
                        .frame(width: 80, height: 80)
                        .shadow(
                            color: (viewModel.phase == .recording ? Color.red : Color.maeusPrimary).opacity(0.3),
                            radius: 20, y: 8
                        )

                    if viewModel.phase == .processing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    } else {
                        Image(systemName: viewModel.phase == .recording ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(viewModel.phase == .processing)

            // Labels
            Text(viewModel.captureLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.maeusText)

            Text(viewModel.captureHint)
                .font(.caption)
                .foregroundStyle(Color.maeusTextTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var pulseScale: CGFloat {
        viewModel.phase == .recording ? 1.3 : 1.0
    }

    // MARK: - Review Content

    private var reviewContent: some View {
        VStack(spacing: 20) {
            // Hero amount
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("€")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.maeusTextTertiary)

                Text(viewModel.draft.amount.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.maeusText)
            }

            // Detail fields
            VStack(spacing: 12) {
                reviewField("Description", value: viewModel.draft.description.isEmpty ? "—" : viewModel.draft.description)
                reviewField("Date", value: formatReviewDate(viewModel.draft.dateISO))
                reviewField("Split", value: formatReviewSplit())
            }
            .padding(16)
            .glassSurface()
        }
    }

    private func reviewField(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.maeusTextSecondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.maeusText)

            Spacer()
        }
    }

    private func formatReviewDate(_ iso: String) -> String {
        let today = VoiceModeViewModel.todayISOString()
        if iso == today { return "Today" }
        guard let date = Expense.dateFromISO(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }

    private func formatReviewSplit() -> String {
        let mode = viewModel.draft.partnerShareMode ?? .percent
        let value = viewModel.draft.partnerShareValue ?? 50
        switch mode {
        case .percent:
            return "\(Int(value)) %"
        case .fixed:
            return value.euroFormatted
        }
    }

    // MARK: - Error Content

    private var errorContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.maeusDestructive)

            Text(viewModel.errorMessage)
                .font(.subheadline)
                .foregroundStyle(Color.maeusTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Footer Actions

    private var footerActions: some View {
        HStack(spacing: 16) {
            Button("Redo") {
                viewModel.recordAgain()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.maeusPrimary)

            Text("·")
                .foregroundStyle(Color.maeusTextTertiary)

            Button("Edit manually") {
                let draft = viewModel.draft
                viewModel.close()
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    editorVM.prepareFromVoiceDraft(draft)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.maeusPrimary)
        }
    }

    // MARK: - Save

    private func saveVoiceDraft() {
        guard let amount = viewModel.draft.amount, amount > 0 else { return }

        let expense = Expense(
            amount: amount,
            desc: viewModel.draft.description,
            date: Expense.dateFromISO(viewModel.draft.dateISO) ?? Date(),
            splitMode: viewModel.draft.partnerShareMode ?? .percent,
            splitValue: viewModel.draft.partnerShareValue ?? 50
        )

        modelContext.insert(expense)
        try? modelContext.save()

        viewModel.close()
        dismiss()
    }
}
