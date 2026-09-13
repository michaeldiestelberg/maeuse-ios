import SwiftUI
import SwiftData

/// One stable list of drafts, with details for the latest spoken request.
struct VoiceSheet: View {
    @Bindable var viewModel: VoiceModeViewModel
    @State private var showsUnderstanding = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            if !dynamicTypeSize.isAccessibilitySize { listeningHero }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(loc("VoiceYourDrafts"))
                        .font(.system(.headline, design: .rounded, weight: .heavy))

                    if viewModel.drafts.isEmpty {
                        emptyCard
                    }
                    ForEach(viewModel.drafts) { draft in
                        VoiceExpenseDraftCard(draft: draft,
                            wasUpdated: viewModel.updatedExpenseIDs.contains(draft.id),
                            onRemove: { viewModel.removeDraft(draft) })
                    }
                    if !viewModel.clarificationQuestion.isEmpty {
                        Label(viewModel.clarificationQuestion, systemImage: "questionmark.bubble")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.maeusInputBackground, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityIdentifier("voice-clarification")
                    }
                    if !viewModel.latestUnderstanding.isEmpty {
                        understandingDetail
                    }
                    if viewModel.phase == .error {
                        Label(viewModel.errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(Color.maeusDestructive)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.maeusDestructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .foregroundStyle(Color.maeusForeground)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.drafts.map(\.id))
            footer
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .background(Color.maeusBackground.ignoresSafeArea())
        .interactiveDismissDisabled(true)
        .task { viewModel.startSession() }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.cancelSession()
                dismiss()
            } label: {
                MaeuseCloseIcon().frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .background(Color.maeusSurface, in: Circle())
            .overlay(Circle().stroke(Color.maeusCardBorder, lineWidth: 2))
            .accessibilityLabel(loc("Close"))

            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(stateColor).frame(width: 9, height: 9)
                Text(viewModel.stateLabel)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(Color.maeusForeground)
            Spacer(minLength: 0)
            Button { endAndSave() } label: {
                Text(viewModel.drafts.isEmpty ? loc("Save") : loc("VoiceSaveCount", viewModel.drafts.count))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 42)
            }
            .buttonStyle(StampedButtonStyle(fill: .maeusCheese, foreground: .maeusInk,
                cornerRadius: 20, borderColor: .maeusInk, shadow: 2.5))
            .opacity(canSave ? 1 : 0.4)
            .disabled(!canSave)
            .accessibilityIdentifier("voice-save")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var canSave: Bool { viewModel.canSaveDrafts && viewModel.canEndSession }
    private var isProcessing: Bool { viewModel.phase == .thinking || viewModel.phase == .connecting }

    private var listeningHero: some View {
        VStack(spacing: 8) {
            MouseCoin(size: 42, shadow: 3, wigglePeriod: 3.5) {
                VoiceBars(level: viewModel.microphoneLevel, isActive: viewModel.microphoneIsActive)
                    .scaleEffect(0.5)
            }
            HStack(spacing: 7) {
                if isProcessing { ProgressView().controlSize(.mini) }
                Text(loc(isProcessing ? "VoicePreparing" : "VoiceContinue"))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.maeusTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(minHeight: 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var stateColor: Color {
        switch viewModel.phase {
        case .idle, .connecting: return .maeusTextTertiary
        case .listening: return .maeusSuccess
        case .thinking, .finalizing: return .maeusPrimary
        case .error: return .maeusDestructive
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(loc(isProcessing ? "VoiceUnderstandingRequest" : "NothingCapturedYet"))
                .font(.system(.headline, design: .rounded, weight: .bold))
            if isProcessing {
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().frame(height: 12)
                    Capsule().frame(width: 140, height: 12)
                }
                .foregroundStyle(Color.maeusInputBackground)
                .accessibilityHidden(true)
            }
            Text(loc(isProcessing ? "VoiceDraftWillAppear" : "SqueakAway"))
                .font(.callout)
                .foregroundStyle(Color.maeusTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(16)
        .background(Color.maeusSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.maeusCardBorder, lineWidth: 2))
    }

    private var understandingDetail: some View {
        DisclosureGroup(isExpanded: $showsUnderstanding) {
            VStack(alignment: .leading, spacing: 8) {
                Text(loc("VoiceLatestRequest"))
                    .font(.caption)
                    .foregroundStyle(Color.maeusTextSecondary)
                Text(viewModel.latestUnderstanding)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Text(loc("VoiceWhatUnderstood"))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .frame(minHeight: 28)
        }
        .tint(Color.maeusForeground)
        .padding(14)
        .background(Color.maeusSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.maeusCardBorder, lineWidth: 1))
        .accessibilityIdentifier("voice-understanding")
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                footerCount
                Spacer(minLength: 12)
                footerTotal
            }
            VStack(alignment: .leading, spacing: 6) {
                footerCount
                footerTotal
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var footerCount: some View {
        Text(loc(viewModel.drafts.count == 1 ? "VoiceOneDraftUnsaved" : "VoiceDraftsUnsaved", viewModel.drafts.count))
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(Color.maeusTextSecondary)
    }

    private var footerTotal: some View {
        Text(loc("TotalAmount", viewModel.totalAmount.euroFormatted))
            .font(.system(.subheadline, design: .rounded, weight: .heavy).monospacedDigit())
            .foregroundStyle(Color.maeusForeground)
    }

    private func endAndSave() {
        guard canSave else { return }
        viewModel.phase = .finalizing
        for expense in viewModel.expensesForSaving() { modelContext.insert(expense) }
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            viewModel.phase = .error
            viewModel.errorMessage = loc("SaveExpensesFailed", error.localizedDescription)
            return
        }
        viewModel.finishAfterSave()
        dismiss()
    }
}

private struct VoiceBars: View {
    let level: Double
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let heights: [CGFloat] = [26, 32, 22, 34, 20]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion || !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(heights.indices, id: \.self) { index in
                    let pulse = reduceMotion || !isActive ? 0.5 : 0.35 + 0.65 * abs(sin(time * (4.5 + Double(index) * 0.35) + Double(index)))
                    Capsule().fill(Color.maeusInk).frame(width: 5, height: heights[index] * max(CGFloat(level), CGFloat(pulse)))
                }
            }.frame(height: 38)
        }
    }
}

private struct VoiceExpenseDraftCard: View {
    let draft: VoiceExpenseDraft
    let wasUpdated: Bool
    let onRemove: () -> Void
    @State private var highlightsUpdate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(draft.normalizedTitle)
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                Spacer(minLength: 0)
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(loc("VoiceRemoveNamed", draft.normalizedTitle))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    metadata
                    Spacer(minLength: 4)
                    amount
                }
                VStack(alignment: .leading, spacing: 8) {
                    amount
                    metadata
                }
            }
            if !draft.isReadyForSaving {
                Text(loc("VoiceNeedsDetails"))
                    .font(.caption)
                    .foregroundStyle(Color.maeusDestructive)
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(Color.maeusForeground)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack {
                shape.fill(Color.maeusInk).offset(x: 3, y: 4)
                shape.fill(highlightsUpdate ? Color.maeusInputBackground : Color.maeusSurface)
                shape.stroke(highlightsUpdate ? Color.maeusPrimary : Color.maeusCardBorder, lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if highlightsUpdate {
                Text(loc("VoiceUpdated"))
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.maeusCheese, in: Capsule())
                    .foregroundStyle(Color.maeusInk)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.trailing, 48)
                    .offset(y: -9)
            }
        }
        .task(id: draft.lastChangedAt) {
            highlightsUpdate = wasUpdated
            guard wasUpdated else { return }
            do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { highlightsUpdate = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-draft-\(draft.id)")
    }

    private var amount: some View {
        Text(draft.amount == nil ? "—" : draft.normalizedAmount.euroFormatted)
            .font(.system(.title3, design: .rounded, weight: .heavy).monospacedDigit())
            .fixedSize()
            .accessibilityLabel(draft.amount == nil ? loc("VoiceAmountMissing") : draft.normalizedAmount.euroFormatted)
    }

    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { dateChip; splitChip }
            VStack(alignment: .leading, spacing: 6) { dateChip; splitChip }
        }
    }
    private var dateChip: some View { chip(formatDate(draft.dateISO)) }
    private var splitChip: some View { chip(loc("VoicePartnerShare", splitText)) }
    private func chip(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.maeusInputBackground, in: Capsule())
    }
    private var splitText: String {
        switch draft.normalizedSplitMode {
        case .percent: return "\(Int(draft.normalizedSplitValue))%"
        case .fixed: return draft.normalizedSplitValue.euroFormatted
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
