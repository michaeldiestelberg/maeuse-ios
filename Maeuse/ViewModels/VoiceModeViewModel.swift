import Foundation
import Observation
import UIKit
#if targetEnvironment(simulator)
import AVFoundation
#endif

/// Manages a fresh Realtime voice workspace for one expense-capture session.
@MainActor
@Observable
final class VoiceModeViewModel {
    var phase: VoicePhase = .idle
    var isPresented: Bool = false
    var errorMessage: String = ""
    private(set) var understandingHistory: [VoiceUnderstandingEntry] = []
    var clarificationQuestion: String = ""
    var drafts: [VoiceExpenseDraft] = []
    var updatedExpenseIDs: Set<String> = []
    private(set) var changedFieldsByExpenseID: [String: Set<VoiceExpenseMissingField>] = [:]
    private(set) var isUserSpeaking = false
    private var awaitingSpokenResponse = false
    private var processingResponseIDs: Set<String> = []

    var isProcessingRequest: Bool {
        awaitingSpokenResponse || !processingResponseIDs.isEmpty
    }
    var microphoneIsActive: Bool = false
    var microphoneLevel: Double = 0
    var isSaving: Bool = false

    private let realtime = RealtimeVoiceService()
    private var connectionTask: Task<Void, Never>?
    private var hasStartedSession = false
    private var didSignalListeningReady = false

    init() {
        realtime.setDelegate(self)
    }

    var microphoneIsReady: Bool {
        microphoneIsActive && (phase == .listening || phase == .thinking)
    }

    var stateLabel: String {
        switch phase {
        case .idle: return loc("StateReady")
        case .connecting: return loc("StateConnecting")
        case .listening: return loc(microphoneIsReady ? "StateListening" : "StateConnecting")
        case .thinking: return loc(isUserSpeaking ? "StateListeningAndThinking" : "StateThinking")
        case .finalizing: return loc("StateSaving")
        case .error: return loc("StateIssue")
        }
    }

    var canEndSession: Bool {
        !isUserSpeaking && !isProcessingRequest && phase != .connecting && phase != .thinking && phase != .finalizing
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
        microphoneIsActive = true
        microphoneLevel = ProcessInfo.processInfo.arguments.contains("--voice-silent") ? 0 : 0.3
        isPresented = true

        let german = LanguageManager.shared.activeLanguageCode == "de"
        let requests = german
            ? ["Blumen für zwölf Euro gestern.", "Und Kaffee, vier fünfzig.", "Noch ein Film auf Apple TV für drei Euro neunundneunzig, auch gestern."]
            : ["Flowers for twelve euros yesterday.", "And coffee, four fifty.", "An Apple TV film for three euros ninety-nine too, also yesterday."]
        understandingHistory = requests.enumerated().map {
            VoiceUnderstandingEntry(id: "preview-\($0.offset)", text: $0.element)
        }
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
        if ProcessInfo.processInfo.arguments.contains("--voice-meter-audio") {
            drafts = []
            understandingHistory = []
            microphoneLevel = 0
            Task { @MainActor [weak self] in
                do {
                    let url = URL.documentsDirectory.appending(path: "voice-meter-test.wav")
                    let audio = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 1_200) else { return }
                    while audio.framePosition < audio.length {
                        guard let self, self.isPresented else { return }
                        try audio.read(into: buffer, frameCount: 1_200)
                        let samples = buffer.audioBufferList.pointee.mBuffers
                        if let bytes = samples.mData {
                            let pcm = Data(bytes: bytes, count: Int(samples.mDataByteSize))
                            self.realtimeVoiceService(self.realtime, didReceive: .microphoneLevel(VoiceInputMeter.level(pcm16: pcm)))
                        }
                        try await Task.sleep(for: .seconds(Double(buffer.frameLength) / audio.processingFormat.sampleRate))
                    }
                    self?.microphoneLevel = 0
                } catch {
                    self?.phase = .error
                    self?.errorMessage = "Audio meter preview unavailable: \(error.localizedDescription)"
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-connection-error") {
            drafts = []
            understandingHistory = []
            realtimeVoiceService(realtime, didReceive: .error(loc("SessionDisconnectedMsg")))
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-connecting") ||
           ProcessInfo.processInfo.arguments.contains("--voice-connect-transition") {
            drafts = []
            understandingHistory = []
            microphoneIsActive = false
            microphoneLevel = 0
            phase = .connecting
            if ProcessInfo.processInfo.arguments.contains("--voice-connect-transition") {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(6))
                    guard let self, self.isPresented, self.phase == .connecting else { return }
                    self.realtimeVoiceService(self.realtime, didReceive: .microphoneStarted)
                    self.microphoneLevel = ProcessInfo.processInfo.arguments.contains("--voice-silent") ? 0 : 0.45
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-processing") {
            drafts = []
            understandingHistory = []
            microphoneLevel = 0
            realtimeVoiceService(realtime, didReceive: .listeningStopped)
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-processing-existing") {
            microphoneLevel = 0
            realtimeVoiceService(realtime, didReceive: .listeningStopped)
            realtimeVoiceService(realtime, didReceive: .responseStarted(id: "preview-pending", isAppGenerated: false))
            if ProcessInfo.processInfo.arguments.contains("--voice-processing-speaking") {
                realtimeVoiceService(realtime, didReceive: .listeningStarted)
                microphoneLevel = 0.5
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-processing-demo") {
            drafts = []
            understandingHistory = []
            microphoneLevel = 0
            Task { @MainActor [weak self] in
                func pause(_ seconds: Double) async throws {
                    try await Task.sleep(for: .seconds(seconds))
                }
                do {
                    for turn in 0..<3 {
                        try await pause(2)
                        guard let self, self.isPresented else { return }
                        self.realtimeVoiceService(self.realtime, didReceive: .listeningStarted)
                        self.microphoneLevel = 0.6
                        try await pause(2)
                        guard self.isPresented else { return }
                        self.microphoneLevel = 0
                        self.realtimeVoiceService(self.realtime, didReceive: .listeningStopped)
                        let id = "demo-\(turn)"
                        self.realtimeVoiceService(self.realtime, didReceive: .responseStarted(id: id, isAppGenerated: false))
                        try await pause(4)
                        guard self.isPresented else { return }
                        var entries = [VoiceExpenseDraftPayload(id: "flowers", title: german ? "Blumen" : "Flowers",
                            amount: turn == 0 ? 12 : 13.5, dateISO: nil,
                            splitMode: nil, splitValue: nil, confidence: 1, missingFields: [])]
                        if turn == 2 {
                            entries.append(VoiceExpenseDraftPayload(id: "coffee", title: german ? "Kaffee" : "Coffee",
                                amount: 4.5, dateISO: nil, splitMode: nil, splitValue: nil, confidence: 1, missingFields: []))
                        }
                        self.realtimeVoiceService(self.realtime, didReceive: .workspaceSync(VoiceWorkspaceSyncPayload(
                            responseID: id, userUnderstanding: turn == 1
                                ? (german ? "Die Blumen waren dreizehn fünfzig." : "The flowers were thirteen fifty.")
                                : requests[turn == 0 ? 0 : 1],
                            clarificationQuestion: "", expenses: entries,
                            changedExpenseIDs: [turn == 2 ? "coffee" : "flowers"], removedExpenseIDs: [])))
                        self.realtimeVoiceService(self.realtime, didReceive: .responseFinished(id: id))
                    }
                } catch { return }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-clarification") {
            clarificationQuestion = german ? "Wie viel hat der Kaffee gekostet?" : "How much was the coffee?"
            drafts[1].amount = nil
            drafts[1].missingFields = [.amount]
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-correction") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(ProcessInfo.processInfo.arguments.contains("--voice-history-delay") ? 25 : 3))
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

        let previousConnection = connectionTask
        connectionTask = Task { @MainActor in
            // Finish cleanup from a cancelled connection before reusing the service.
            await previousConnection?.value
            guard !Task.isCancelled else { return }
            do {
                try await realtime.connect()
            } catch {
                guard !Task.isCancelled else { return }
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
        changedFieldsByExpenseID[draft.id] = nil
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
        connectionTask?.cancel()
        phase = .idle
        errorMessage = ""
        understandingHistory = []
        clarificationQuestion = ""
        drafts = []
        updatedExpenseIDs = []
        changedFieldsByExpenseID = [:]
        clearProcessingState()
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
        let understanding = payload.userUnderstanding.trimmingCharacters(in: .whitespacesAndNewlines)
        let entryID = payload.responseID ?? UUID().uuidString
        // Keep completed requests immutable, even if a response includes multiple tool calls.
        // Identical words in a different response still represent another spoken request.
        if !payload.isAppGenerated, !understanding.isEmpty, !understandingHistory.contains(where: { $0.id == entryID }) {
            understandingHistory.append(VoiceUnderstandingEntry(id: entryID, text: understanding))
        }
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

        changedFieldsByExpenseID = Dictionary(uniqueKeysWithValues: nextDrafts.compactMap { draft in
            guard let previous = previousDrafts[draft.id] else { return nil }
            return (draft.id, draft.changedFields(comparedTo: previous))
        })
        updatedExpenseIDs = updatedIDs
        drafts = nextDrafts

        if !addedIDs.isEmpty {
            playVoiceHaptic(.success)
        } else if !updatedIDs.isEmpty {
            playVoiceHaptic(.soft)
        }

        // A completed result must not hide another request that is still pending.
        processingResponseIDs.remove(payload.responseID ?? "unidentified-response")
        refreshActivityPhase()
    }

    private func refreshActivityPhase() {
        guard phase != .error && phase != .finalizing else { return }
        phase = isProcessingRequest ? .thinking : .listening
    }

    private func clearProcessingState() {
        awaitingSpokenResponse = false
        processingResponseIDs = []
        isUserSpeaking = false
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
            phase = microphoneIsActive ? .listening : .connecting
        case .disconnected:
            clearProcessingState()
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
            if phase != .error && phase != .finalizing { phase = .listening }
            if !didSignalListeningReady {
                didSignalListeningReady = true
                playVoiceHaptic(.rigid)
            }
        case .microphoneStopped:
            isUserSpeaking = false
            microphoneIsActive = false
            microphoneLevel = 0
        case .microphoneLevel(let level):
            microphoneLevel = level
        case .listeningStarted:
            isUserSpeaking = true
            refreshActivityPhase()
        case .listeningStopped:
            isUserSpeaking = false
            awaitingSpokenResponse = true
            refreshActivityPhase()
        case .responseStarted(let id, let isAppGenerated):
            if !isAppGenerated { awaitingSpokenResponse = false }
            processingResponseIDs.insert(id)
            refreshActivityPhase()
        case .responseFinished(let id):
            processingResponseIDs.remove(id)
            refreshActivityPhase()
        case .workspaceSync(let payload):
            applyWorkspaceSync(payload)
        case .assistantText, .assistantTextDelta:
            // Incidental model narration must not race the structured draft update.
            break
        case .error(let message):
            clearProcessingState()
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
