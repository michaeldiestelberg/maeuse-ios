import Foundation
import Observation

/// Manages a fresh Realtime voice workspace for one expense-capture session.
@MainActor
@Observable
final class VoiceModeViewModel {
    var phase: VoicePhase = .idle
    var isPresented: Bool = false
    var errorMessage: String = ""
    var conversation: [VoiceConversationEntry] = []
    var drafts: [VoiceExpenseDraft] = []
    var liveUserTranscript: String = ""
    var liveAssistantText: String = ""
    var changedExpenseIDs: Set<String> = []
    var microphoneIsActive: Bool = false
    var microphoneLevel: Double = 0
    var isSaving: Bool = false

    private let realtime = RealtimeVoiceService()
    private var hasStartedSession = false
    private var userTranscriptBuffers: [String: String] = [:]
    private var activeUserTranscriptID: String?

    init() {
        realtime.setDelegate(self)
    }

    var stateLabel: String {
        switch phase {
        case .idle: return "Ready"
        case .connecting: return "Connecting"
        case .listening:
            if microphoneIsActive {
                return "Listening · Mic \(Int(microphoneLevel * 100))%"
            }
            return "Listening"
        case .thinking: return "Updating"
        case .finalizing: return "Saving"
        case .error: return "Issue"
        }
    }

    var canEndSession: Bool {
        phase != .connecting && phase != .finalizing
    }

    var savedButtonTitle: String {
        drafts.isEmpty ? "End" : "End & Save"
    }

    var totalAmount: Double {
        drafts.reduce(0) { $0 + $1.normalizedAmount }.roundedMoney
    }

    var partnerTotal: Double {
        drafts.reduce(0) { $0 + $1.partnerShare }.roundedMoney
    }

    var takeawayText: String {
        guard !drafts.isEmpty else { return "No expenses captured yet" }
        let count = drafts.count == 1 ? "1 expense" : "\(drafts.count) expenses"
        return "\(count) · \(totalAmount.euroFormatted) total · \(partnerTotal.euroFormatted) partner"
    }

    // MARK: - Actions

    func open() {
        resetWorkspace()
        isPresented = true
    }

    func startSession() {
        guard !hasStartedSession else { return }

        hasStartedSession = true
        phase = .connecting

        Task { @MainActor in
            do {
                try await realtime.connect()
            } catch {
                phase = .error
                errorMessage = error.localizedDescription
                appendLog(.system, "Connection failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelSession() {
        realtime.disconnect()
        resetWorkspace()
        isPresented = false
    }

    func finishAfterSave() {
        realtime.disconnect()
        resetWorkspace()
        isPresented = false
    }

    func removeDraft(_ draft: VoiceExpenseDraft) {
        drafts.removeAll { $0.id == draft.id }
        changedExpenseIDs = [draft.id]
        appendLog(.system, "Removed \(draft.normalizedTitle).")
        realtime.sendWorkspaceNote("The user removed expense \(draft.id) named \(draft.normalizedTitle) from the temporary workspace. Keep it removed unless the user asks to add it again.")
    }

    func expensesForSaving() -> [Expense] {
        let todayISO = Self.todayISOString()
        return drafts.map { draft in
            Expense(
                amount: draft.normalizedAmount,
                desc: draft.normalizedTitle,
                date: draft.normalizedDate(defaultISO: todayISO),
                splitMode: draft.normalizedSplitMode,
                splitValue: draft.normalizedSplitValue
            )
        }
    }

    func resetWorkspace() {
        phase = .idle
        errorMessage = ""
        conversation = []
        drafts = []
        liveUserTranscript = ""
        liveAssistantText = ""
        changedExpenseIDs = []
        microphoneIsActive = false
        microphoneLevel = 0
        isSaving = false
        hasStartedSession = false
        userTranscriptBuffers = [:]
        activeUserTranscriptID = nil
    }

    static func todayISOString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    // MARK: - Workspace Sync

    private func applyWorkspaceSync(_ payload: VoiceWorkspaceSyncPayload) {
        appendLog(.assistant, payload.assistantConfirmation)

        let todayISO = Self.todayISOString()
        let previousDrafts = drafts.reduce(into: [String: VoiceExpenseDraft]()) { result, draft in
            result[draft.id] = draft
        }
        let explicitChanges = Set(payload.changedExpenseIDs + payload.removedExpenseIDs)

        let nextDrafts = payload.expenses.map { payloadDraft -> VoiceExpenseDraft in
            var next = applyDefaultWorkspaceFields(to: payloadDraft.draft, todayISO: todayISO)
            if let previous = previousDrafts[next.id],
               previous.withoutChangeTimestamp == next.withoutChangeTimestamp,
               !explicitChanges.contains(next.id) {
                next.lastChangedAt = previous.lastChangedAt
            }
            return next
        }

        changedExpenseIDs = Set(nextDrafts.compactMap { draft in
            let previous = previousDrafts[draft.id]
            if explicitChanges.contains(draft.id) || previous?.withoutChangeTimestamp != draft.withoutChangeTimestamp {
                return draft.id
            }
            return nil
        }).union(payload.removedExpenseIDs)

        drafts = nextDrafts
        liveAssistantText = ""

        if phase != .error {
            phase = .listening
        }
    }

    private func appendLog(_ role: VoiceConversationRole, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if conversation.last?.role == role, conversation.last?.text == trimmed {
            return
        }

        conversation.append(VoiceConversationEntry(role: role, text: trimmed))
    }

    private func applyUserTranscriptDelta(itemID: String, text: String) {
        let key = transcriptKey(for: itemID)
        userTranscriptBuffers[key, default: ""] += text
        activeUserTranscriptID = key
        liveUserTranscript = userTranscriptBuffers[key] ?? ""
    }

    private func finishUserTranscript(itemID: String, text: String) {
        let key = transcriptKey(for: itemID)
        let fallbackText = userTranscriptBuffers[key] ?? ""
        let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackText : text

        userTranscriptBuffers[key] = nil
        if activeUserTranscriptID == key {
            activeUserTranscriptID = nil
            liveUserTranscript = nextLiveUserTranscript()
        }

        appendLog(.user, transcript)
    }

    private func transcriptKey(for itemID: String) -> String {
        itemID.isEmpty ? "default" : itemID
    }

    private func nextLiveUserTranscript() -> String {
        guard let next = userTranscriptBuffers.first else { return "" }
        activeUserTranscriptID = next.key
        return next.value
    }

    private func applyDefaultWorkspaceFields(to draft: VoiceExpenseDraft, todayISO: String) -> VoiceExpenseDraft {
        var draft = draft
        if draft.dateISO == nil {
            draft.dateISO = todayISO
        }
        if draft.splitMode == nil {
            draft.splitMode = .percent
        }
        if draft.splitValue == nil {
            draft.splitValue = 50
        }
        draft.missingFields.removeAll { $0 == .date || $0 == .split }
        return draft
    }
}

extension VoiceModeViewModel: RealtimeVoiceServiceDelegate {
    func realtimeVoiceService(_ service: RealtimeVoiceService, didReceive event: RealtimeVoiceServiceEvent) {
        switch event {
        case .connected:
            phase = .listening
        case .disconnected:
            microphoneIsActive = false
            microphoneLevel = 0
            if phase != .finalizing && phase != .idle {
                phase = .error
                errorMessage = "The Realtime session disconnected."
            }
        case .microphoneReady:
            break
        case .microphoneStarted:
            microphoneIsActive = true
        case .microphoneStopped:
            microphoneIsActive = false
            microphoneLevel = 0
        case .microphoneLevel(let level):
            microphoneLevel = level
        case .listeningStarted:
            phase = .listening
        case .listeningStopped:
            phase = .thinking
        case .responseStarted:
            phase = .thinking
        case .responseFinished:
            if phase != .error {
                phase = .listening
            }
        case .workspaceSync(let payload):
            applyWorkspaceSync(payload)
        case .userTranscriptDelta(let itemID, let text):
            applyUserTranscriptDelta(itemID: itemID, text: text)
        case .userTranscriptDone(let itemID, let text):
            finishUserTranscript(itemID: itemID, text: text)
        case .assistantText(let text):
            appendLog(.assistant, text)
            liveAssistantText = ""
        case .assistantTextDelta(let text):
            liveAssistantText += text
        case .error(let message):
            phase = .error
            errorMessage = message
            appendLog(.system, message)
        }
    }
}

private extension VoiceExpenseDraft {
    var withoutChangeTimestamp: VoiceExpenseDraft {
        VoiceExpenseDraft(
            id: id,
            title: title,
            amount: amount,
            dateISO: dateISO,
            splitMode: splitMode,
            splitValue: splitValue,
            confidence: confidence,
            missingFields: missingFields,
            lastChangedAt: .distantPast
        )
    }
}
