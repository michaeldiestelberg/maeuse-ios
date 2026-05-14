import SwiftUI
import SwiftData

/// Full-screen Realtime voice workspace for capturing one or more expenses.
struct VoiceSheet: View {
    @Bindable var viewModel: VoiceModeViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                Divider().opacity(0.25)

                conversationArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                workspaceArea
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .interactiveDismissDisabled(true)
        .task {
            viewModel.startSession()
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color.maeusBackground,
                Color.maeusSurface,
                Color.maeusBackground
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.cancelSession()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.maeusTextSecondary)
            .background(.ultraThinMaterial)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Expense")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.maeusText)

                HStack(spacing: 6) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 8, height: 8)
                    Text(viewModel.stateLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.maeusTextSecondary)
                }
            }

            Spacer()

            Button {
                endAndSave()
            } label: {
                Label(viewModel.savedButtonTitle, systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.maeusPrimary)
            .disabled(!viewModel.canEndSession)
        }
    }

    private var stateColor: Color {
        switch viewModel.phase {
        case .idle, .connecting:
            return Color.maeusTextTertiary
        case .listening:
            return Color.maeusSuccess
        case .thinking:
            return Color.maeusPrimary
        case .finalizing:
            return Color.maeusPrimary
        case .error:
            return Color.maeusDestructive
        }
    }

    private var conversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if viewModel.conversation.isEmpty && viewModel.liveUserTranscript.isEmpty && viewModel.liveAssistantText.isEmpty {
                        emptyConversation
                            .padding(.top, 64)
                    }

                    ForEach(viewModel.conversation) { entry in
                        ConversationBubble(entry: entry)
                            .id(entry.id)
                    }

                    if !viewModel.liveUserTranscript.isEmpty {
                        ConversationBubble(
                            entry: VoiceConversationEntry(
                                role: .user,
                                text: viewModel.liveUserTranscript
                            ),
                            isLive: true
                        )
                        .id("live-user-transcript")
                    }

                    if !viewModel.liveAssistantText.isEmpty {
                        ConversationBubble(
                            entry: VoiceConversationEntry(
                                role: .assistant,
                                text: viewModel.liveAssistantText
                            ),
                            isLive: true
                        )
                        .id("live-assistant-text")
                    }

                    if viewModel.phase == .error {
                        errorBanner
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .onChange(of: viewModel.conversation) { _, entries in
                guard let last = entries.last else { return }
                withAnimation(.spring(duration: 0.3)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.liveUserTranscript) { _, transcript in
                guard !transcript.isEmpty else { return }
                withAnimation(.spring(duration: 0.3)) {
                    proxy.scrollTo("live-user-transcript", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.liveAssistantText) { _, text in
                guard !text.isEmpty else { return }
                withAnimation(.spring(duration: 0.3)) {
                    proxy.scrollTo("live-assistant-text", anchor: .bottom)
                }
            }
        }
    }

    private var emptyConversation: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.maeusPrimary.opacity(0.14))
                    .frame(width: 86, height: 86)

                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.maeusPrimary)
            }

            Text(viewModel.phase == .connecting ? "Connecting" : "Listening")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.maeusText)
        }
        .frame(maxWidth: .infinity)
    }

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.maeusDestructive)

            Text(viewModel.errorMessage)
                .font(.caption)
                .foregroundStyle(Color.maeusTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.maeusDestructive.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var workspaceArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Workspace")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.maeusTextSecondary)
                    Text(viewModel.takeawayText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.maeusText)
                        .monospacedDigit()
                }

                Spacer()

                Image(systemName: viewModel.drafts.isEmpty ? "tray" : "sum")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.maeusPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.maeusPrimary.opacity(0.1))
                    .clipShape(Circle())
            }

            if viewModel.drafts.isEmpty {
                Text("No expenses yet")
                    .font(.caption)
                    .foregroundStyle(Color.maeusTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.drafts) { draft in
                            VoiceExpenseDraftCard(
                                draft: draft,
                                isChanged: viewModel.changedExpenseIDs.contains(draft.id),
                                onRemove: {
                                    withAnimation(.spring(duration: 0.25)) {
                                        viewModel.removeDraft(draft)
                                    }
                                }
                            )
                            .frame(width: 260)
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(16)
        .glassSurface(elevated: true)
        .animation(.spring(duration: 0.3), value: viewModel.drafts)
    }

    private func endAndSave() {
        viewModel.phase = .finalizing

        for expense in viewModel.expensesForSaving() {
            modelContext.insert(expense)
        }
        try? modelContext.save()

        viewModel.finishAfterSave()
        dismiss()
    }
}

private struct ConversationBubble: View {
    let entry: VoiceConversationEntry
    var isLive: Bool = false

    var body: some View {
        HStack {
            if entry.role == .user { Spacer(minLength: 44) }

            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(labelColor)

                Text(entry.text)
                    .font(.subheadline)
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isLive ? 0.75 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(backgroundStyle)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if entry.role != .user { Spacer(minLength: 44) }
        }
    }

    private var label: String {
        switch entry.role {
        case .user: return "You"
        case .assistant: return "Mäuse"
        case .system: return "Session"
        }
    }

    private var labelColor: Color {
        switch entry.role {
        case .user: return .white.opacity(0.8)
        case .assistant: return Color.maeusPrimary
        case .system: return Color.maeusTextTertiary
        }
    }

    private var textColor: Color {
        entry.role == .user ? .white : Color.maeusText
    }

    private var backgroundStyle: some ShapeStyle {
        switch entry.role {
        case .user:
            return AnyShapeStyle(Color.maeusPrimary)
        case .assistant:
            return AnyShapeStyle(.ultraThinMaterial)
        case .system:
            return AnyShapeStyle(Color.maeusInputBackground.opacity(0.7))
        }
    }
}

private struct VoiceExpenseDraftCard: View {
    let draft: VoiceExpenseDraft
    let isChanged: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.normalizedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.maeusText)
                        .lineLimit(2)

                    Text(formatDate(draft.dateISO))
                        .font(.caption)
                        .foregroundStyle(Color.maeusTextTertiary)
                }

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.maeusTextTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove expense")
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(draft.normalizedAmount.euroFormatted)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.maeusText)

                Spacer()

                Text(splitText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.maeusPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.maeusPrimary.opacity(0.1))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                confidenceBadge

                if !draft.missingFields.isEmpty {
                    missingBadge
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isChanged ? Color.maeusPrimary.opacity(0.8) : Color(UIColor.separator).opacity(0.25), lineWidth: isChanged ? 1.5 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .scaleEffect(isChanged ? 1.015 : 1)
        .animation(.spring(duration: 0.25), value: isChanged)
    }

    private var confidenceBadge: some View {
        Text("\(Int(draft.confidence * 100))%")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.maeusTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.maeusInputBackground)
            .clipShape(Capsule())
    }

    private var missingBadge: some View {
        Text("Missing \(draft.missingFields.map(\.rawValue).joined(separator: ", "))")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.maeusDestructive)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.maeusDestructive.opacity(0.08))
            .clipShape(Capsule())
    }

    private var splitText: String {
        switch draft.normalizedSplitMode {
        case .percent:
            return "\(Int(draft.normalizedSplitValue))%"
        case .fixed:
            return draft.normalizedSplitValue.euroFormatted
        }
    }

    private func formatDate(_ iso: String?) -> String {
        guard let iso, let date = Expense.dateFromISO(iso) else { return "Today" }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }
}
