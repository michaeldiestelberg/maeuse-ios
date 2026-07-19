import Foundation
import Observation
import UIKit

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
    private var didSignalListeningReady = false
    private var userTranscriptBuffers: [String: String] = [:]
    private var activeUserTranscriptID: String?

    init() {
        realtime.setDelegate(self)
    }

    var stateLabel: String {
        switch phase {
        case .idle: return loc("StateReady")
        case .connecting: return loc("StateConnecting")
        case .listening: return loc("StateListening")
        case .thinking: return loc("StateThinking")
        case .finalizing: return loc("StateSaving")
        case .error: return loc("StateIssue")
        }
    }

    var canEndSession: Bool {
        phase != .connecting && phase != .finalizing
    }

    var canSaveDrafts: Bool {
        !drafts.isEmpty && drafts.allSatisfy(\.isReadyForSaving)
    }

    var totalAmount: Double {
        drafts.reduce(0) { $0 + $1.normalizedAmount }.roundedMoney
    }

    var partnerTotal: Double {
        drafts.reduce(0) { $0 + $1.partnerShare }.roundedMoney
    }

    var takeawayText: String {
        guard !drafts.isEmpty else { return loc("NoExpensesCaptured") }
        let countText = drafts.count == 1 ? loc("OneExpense") : loc("MultiExpenses", drafts.count)
        return loc("WorkspaceSummary", countText, totalAmount.euroFormatted, partnerTotal.euroFormatted)
    }

    // MARK: - Actions

    func open() {
        resetWorkspace()
        isPresented = true
    }

    #if targetEnvironment(simulator)
    func openScreenshotPreview() {
        resetWorkspace()
        hasStartedSession = true
        phase = .listening
        isPresented = true

        let german = LanguageManager.shared.activeLanguageCode == "de"
        conversation = [
            VoiceConversationEntry(
                role: .user,
                text: german
                    ? "Blumen für 12 Euro und Kinokarten für 24 Euro, beides halbe-halbe."
                    : "Flowers for 12 euros and cinema tickets for 24 euros, split both in half."
            ),
            VoiceConversationEntry(
                role: .assistant,
                text: german
                    ? "Zwei Ausgaben erfasst und jeweils 50/50 aufgeteilt."
                    : "Captured two expenses and split each one 50/50."
            )
        ]
        drafts = [
            VoiceExpenseDraft(
                id: "screenshot-flowers",
                title: german ? "Blumen" : "Flowers",
                amount: 12,
                dateISO: Self.todayISOString(),
                splitMode: .percent,
                splitValue: 50,
                confidence: 1,
                missingFields: []
            ),
            VoiceExpenseDraft(
                id: "screenshot-cinema",
                title: german ? "Kinokarten" : "Cinema tickets",
                amount: 24,
                dateISO: Self.todayISOString(),
                splitMode: .percent,
                splitValue: 50,
                confidence: 1,
                missingFields: []
            )
        ]
    }
    #endif

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
        guard canSaveDrafts else { return [] }

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
        didSignalListeningReady = false
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

        let previousIDs = Set(previousDrafts.keys)
        let nextIDs = Set(nextDrafts.map(\.id))
        let addedIDs = nextIDs.subtracting(previousIDs)
        // Content-only: ignore changed_expense_ids claims with identical fields.
        let updatedIDs = Set(nextDrafts.compactMap { draft -> String? in
            guard let previous = previousDrafts[draft.id] else { return nil }
            return previous.withoutChangeTimestamp != draft.withoutChangeTimestamp ? draft.id : nil
        })

        drafts = nextDrafts
        liveAssistantText = ""

        if !addedIDs.isEmpty {
            playVoiceHaptic(.success)
        } else if !updatedIDs.isEmpty {
            playVoiceHaptic(.soft)
        }

        if phase != .error {
            phase = .listening
        }
    }

    private var areVoiceHapticsEnabled: Bool {
        guard let data = UserDefaults.standard.data(forKey: VoiceSettings.storageKey),
              let settings = try? JSONDecoder().decode(VoiceSettings.self, from: data) else {
            return true
        }
        return settings.hapticsEnabled
    }

    private enum VoiceHapticStyle {
        case success
        case soft
        case rigid
    }

    private func playVoiceHaptic(_ style: VoiceHapticStyle) {
        guard areVoiceHapticsEnabled else { return }
        switch style {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .soft:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .rigid:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
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
                errorMessage = loc("SessionDisconnectedMsg")
            }
        case .microphoneReady:
            break
        case .microphoneStarted:
            microphoneIsActive = true
            if !didSignalListeningReady {
                didSignalListeningReady = true
                playVoiceHaptic(.rigid)
            }
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
