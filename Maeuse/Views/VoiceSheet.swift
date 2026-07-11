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
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                listeningHero

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
        Color.maeusBackground
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Button {
                    viewModel.cancelSession()
                    dismiss()
                } label: {
                    MaeuseCloseIcon().frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .background(Color.maeusSurface, in: Circle())
                .overlay(Circle().stroke(Color.maeusCardBorder, lineWidth: 2))

                Spacer()

                Button { endAndSave() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))

                        Text(loc("Save"))
                    }
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                }
                .buttonStyle(StampedButtonStyle(fill: .maeusCheese, foreground: .maeusInk, cornerRadius: 18, borderColor: .maeusInk, shadow: 2.5))
                .opacity(viewModel.canSaveDrafts ? 1 : 0.4)
                .disabled(!viewModel.canSaveDrafts || !viewModel.canEndSession)
            }

            HStack(spacing: 8) {
                Circle().fill(stateColor).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.maeusCardBorder, lineWidth: 2))
                Text(viewModel.stateLabel)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.maeusForeground)
                    .lineLimit(1)
            }
        }
    }

    private var listeningHero: some View {
        VStack(spacing: 12) {
            MouseCoin(size: 84, shadow: 5, wigglePeriod: 3.5) {
                VoiceBars(level: viewModel.microphoneLevel)
            }
            Text(loc("SqueakAway"))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.maeusTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 4)
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
                Text(loc("InTheTrap", viewModel.drafts.count).uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.5)
                    .foregroundStyle(Color.maeusTextSecondary)

                Spacer()

                if !viewModel.drafts.isEmpty {
                    Text(loc("TotalAmount", viewModel.totalAmount.euroFormatted))
                        .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Color.maeusPrimaryHover)
                }
            }

            if viewModel.drafts.isEmpty {
                Text(loc("NothingCapturedYet"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.maeusTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.drafts) { draft in
                            VoiceExpenseDraftCard(
                                draft: draft,
                                onRemove: {
                                    withAnimation(.spring(duration: 0.25)) {
                                        viewModel.removeDraft(draft)
                                    }
                                }
                            )
                            .frame(width: 156)
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.horizontal, 11).padding(.top, 14)
        .animation(.spring(duration: 0.3), value: viewModel.drafts)
    }

    private func endAndSave() {
        guard viewModel.canSaveDrafts else { return }
        viewModel.phase = .finalizing

        for expense in viewModel.expensesForSaving() {
            modelContext.insert(expense)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            viewModel.phase = .error
            viewModel.errorMessage = loc("SaveExpensesFailed", error.localizedDescription)
            return
        }

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
                Text(entry.text)
                    .font(.system(size: 14, weight: entry.role == .user ? .semibold : .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isLive ? 0.75 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(backgroundStyle)
            .overlay(bubbleShape.stroke(entry.role == .assistant ? Color.maeusCardBorder : .clear, lineWidth: 2))
            .clipShape(bubbleShape)

            if entry.role != .user { Spacer(minLength: 44) }
        }
    }

    private var label: String {
        switch entry.role {
        case .user: return loc("You")
        case .assistant: return loc("Maeuse")
        case .system: return loc("Session")
        }
    }

    private var labelColor: Color {
        switch entry.role {
        case .user: return Color.maeusInk.opacity(0.7)
        case .assistant: return Color.maeusPrimary
        case .system: return Color.maeusTextTertiary
        }
    }

    private var textColor: Color {
        entry.role == .user ? .white : Color.maeusForeground
    }

    private var backgroundStyle: some ShapeStyle {
        switch entry.role {
        case .user:
            return AnyShapeStyle(Color.maeusInk)
        case .assistant:
            return AnyShapeStyle(Color.maeusSurface)
        case .system:
            return AnyShapeStyle(Color.maeusInputBackground.opacity(0.7))
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 18,
                bottomLeading: entry.role == .user ? 18 : 4,
                bottomTrailing: entry.role == .user ? 4 : 18,
                topTrailing: 18
            ),
            style: .continuous
        )
    }
}

private struct VoiceBars: View {
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let heights: [CGFloat] = [26, 32, 22, 34, 20]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(heights.indices, id: \.self) { index in
                    let pulse = reduceMotion ? 1 : 0.35 + 0.65 * abs(sin(time * (4.5 + Double(index) * 0.35) + Double(index)))
                    Capsule().fill(Color.maeusInk).frame(width: 5, height: heights[index] * max(CGFloat(level), CGFloat(pulse)))
                }
            }.frame(height: 38)
        }
    }
}

private struct VoiceExpenseDraftCard: View {
    let draft: VoiceExpenseDraft
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(draft.normalizedTitle)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.maeusForeground)
                    .lineLimit(1)

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.maeusTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(loc("RemoveExpense"))
            }

            Text(draft.normalizedAmount.euroFormatted)
                .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.maeusForeground)

            HStack(spacing: 6) {
                Text(splitText)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.maeusInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.maeusCheese)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.maeusInk, lineWidth: 1.5))

                Text(formatDate(draft.dateISO))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.maeusTextSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.maeusInputBackground)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            ZStack {
                shape.fill(Color.maeusInk).offset(x: 4, y: 4)
                shape.fill(Color.maeusSurface)
                shape.stroke(Color.maeusInk, lineWidth: 2.5)
            }
        }
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
        guard let iso, let date = Expense.dateFromISO(iso) else { return loc("Today") }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return loc("Today") }
        if calendar.isDateInYesterday(date) { return loc("Yesterday") }
        if calendar.isDateInTomorrow(date) { return loc("Tomorrow") }

        let formatter = DateFormatter()
        formatter.dateFormat = LanguageManager.shared.activeLanguageCode == "de" ? "d. MMM" : "d MMM"
        formatter.locale = LanguageManager.shared.activeLocale
        return formatter.string(from: date)
    }
}
