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
    var latestUnderstanding: String = ""
    var clarificationQuestion: String = ""
    var drafts: [VoiceExpenseDraft] = []
    var updatedExpenseIDs: Set<String> = []
    var microphoneIsActive: Bool = false
    var microphoneLevel: Double = 0
    var isSaving: Bool = false

    private let realtime = RealtimeVoiceService()
    private var hasStartedSession = false
    private var didSignalListeningReady = false

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
        phase != .connecting && phase != .thinking && phase != .finalizing
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
        latestUnderstanding = german
            ? "Blumen für 12 Euro, Kaffee für 4,50 Euro und ein Film auf Apple TV für 3,99 Euro. Alles gestern, jeweils halbe-halbe."
            : "Flowers for 12 euros, coffee for 4.50 euros and an Apple TV film for 3.99 euros. All yesterday, split equally."
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        drafts = [
            ("flowers", german ? "Blumen" : "Flowers", 12.0),
            ("coffee", german ? "Kaffee" : "Coffee", 4.5),
            ("film", german ? "Film auf Apple TV" : "Film on Apple TV", 3.99)
        ].map { id, title, amount in
            VoiceExpenseDraft(id: id, title: title, amount: amount,
                              dateISO: formatter.string(from: yesterday), splitMode: .percent,
                              splitValue: 50, confidence: 1, missingFields: [])
        }
        // Simulator-only fixtures exercise the production event handler and layout.
        if ProcessInfo.processInfo.arguments.contains("--voice-processing") {
            drafts = []
            latestUnderstanding = ""
            phase = .thinking
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-clarification") {
            clarificationQuestion = german ? "Wie viel hat der Kaffee gekostet?" : "How much was the coffee?"
            drafts[1].amount = nil
            drafts[1].missingFields = [.amount]
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-correction") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.isPresented, self.drafts.count == 3 else { return }
                let corrected = self.drafts.map { draft in
                    VoiceExpenseDraftPayload(id: draft.id, title: draft.title,
                        amount: draft.id == "flowers" ? 13.5 : draft.amount,
                        dateISO: draft.dateISO, splitMode: "percent", splitValue: 50,
                        confidence: 1, missingFields: [])
                }
                self.applyWorkspaceSync(VoiceWorkspaceSyncPayload(
                    userUnderstanding: german ? "Die Blumen haben 13,50 Euro gekostet, nicht 12 Euro." : "The flowers were 13.50 euros, not 12 euros.",
                    clarificationQuestion: "", expenses: corrected,
                    changedExpenseIDs: ["flowers"], removedExpenseIDs: []))
            }
        }
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
        updatedExpenseIDs.remove(draft.id)
        latestUnderstanding = ""
        clarificationQuestion = ""
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
        latestUnderstanding = ""
        clarificationQuestion = ""
        drafts = []
        updatedExpenseIDs = []
        microphoneIsActive = false
        microphoneLevel = 0
        isSaving = false
        hasStartedSession = false
        didSignalListeningReady = false
    }

    static func todayISOString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    // MARK: - Workspace Sync

    private func applyWorkspaceSync(_ payload: VoiceWorkspaceSyncPayload) {
        latestUnderstanding = payload.userUnderstanding.trimmingCharacters(in: .whitespacesAndNewlines)
        clarificationQuestion = payload.clarificationQuestion.trimmingCharacters(in: .whitespacesAndNewlines)

        let todayISO = Self.todayISOString()
        let previousDrafts = drafts.reduce(into: [String: VoiceExpenseDraft]()) { result, draft in
            result[draft.id] = draft
        }

        let incomingDrafts = payload.expenses.map { payloadDraft -> VoiceExpenseDraft in
            var next = applyDefaultWorkspaceFields(to: payloadDraft.draft, todayISO: todayISO)
            if let previous = previousDrafts[next.id],
               previous.withoutChangeTimestamp == next.withoutChangeTimestamp {
                next.lastChangedAt = previous.lastChangedAt
            }
            return next
        }

        // Keep existing cards in place even if the model reorders its full workspace.
        let incomingByID = Dictionary(incomingDrafts.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let previousOrder = drafts.map(\.id)
        var seen = Set(previousOrder)
        let newIDs = incomingDrafts.compactMap { seen.insert($0.id).inserted ? $0.id : nil }
        let nextDrafts = (previousOrder + newIDs).compactMap { incomingByID[$0] }

        let previousIDs = Set(previousDrafts.keys)
        let nextIDs = Set(nextDrafts.map(\.id))
        let addedIDs = nextIDs.subtracting(previousIDs)
        // Content-only: ignore changed_expense_ids claims with identical fields.
        let updatedIDs = Set(nextDrafts.compactMap { draft -> String? in
            guard let previous = previousDrafts[draft.id] else { return nil }
            return previous.withoutChangeTimestamp != draft.withoutChangeTimestamp ? draft.id : nil
        })

        updatedExpenseIDs = updatedIDs
        drafts = nextDrafts

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
        case .assistantText, .assistantTextDelta:
            // Incidental model narration must not race the structured draft update.
            break
        case .error(let message):
            phase = .error
            errorMessage = message
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
            confidence: 0, // Model confidence alone is not a visible correction.
            missingFields: missingFields,
            lastChangedAt: .distantPast
        )
    }
}
