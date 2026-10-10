import AVFoundation
import Foundation
import FoundationModels
@preconcurrency import Speech
import UIKit

enum LocalVoiceAvailability: Equatable {
    case available, needsOS, deviceNotEligible, intelligenceDisabled, modelNotReady, unsupportedLanguage, speechUnavailable

    var message: String {
        switch self {
        case .available: return loc("LocalAvailable")
        case .needsOS: return loc("LocalNeedsOS")
        case .deviceNotEligible: return loc("LocalDeviceUnsupported")
        case .intelligenceDisabled: return loc("LocalIntelligenceDisabled")
        case .modelNotReady: return loc("LocalModelNotReady")
        case .unsupportedLanguage: return loc("LocalLanguageUnsupported")
        case .speechUnavailable: return loc("LocalSpeechUnavailable")
        }
    }

    @MainActor static var current: Self {
        guard #available(iOS 26.0, *) else { return .needsOS }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available: break
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .intelligenceDisabled
        case .unavailable(.modelNotReady): return .modelNotReady
        case .unavailable: return .modelNotReady
        }
        guard model.supportsLocale(AppleLocalVoiceService.locale) else { return .unsupportedLanguage }
        guard let recognizer = SFSpeechRecognizer(locale: AppleLocalVoiceService.locale),
              recognizer.supportsOnDeviceRecognition else { return .speechUnavailable }
        return .available
    }
}

struct LocalVoiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Apple speech recognition (strictly offline) followed by the on-device system model.
/// This service has no credentials, network client, or reference to the cloud service.
@MainActor
final class AppleLocalVoiceService: VoiceSessionService {
    var onEvent: ((RealtimeVoiceServiceEvent) -> Void)?
    static var locale: Locale {
        Locale(identifier: LanguageManager.shared.activeLanguageCode == "de" ? "de-DE" : "en-US")
    }

    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timer: Task<Void, Never>?
    private var generation: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var identity = UUID()
    private var transcript = ""
    private var context: String?
    private var finishing = false
    private var generating = false
    private var ownsAudioSession = false
    private var endpoint = LocalSpeechEndpoint()
    private var trace: LocalVoiceTrace?
    private var captureEndReason = "asr-final"
    private let processingTimeout: Duration
    private let processor: @MainActor (String, String?, LocalVoiceTrace?) async throws -> VoiceWorkspaceSyncPayload

    init(processingTimeout: Duration = .seconds(60),
         processor: @escaping @MainActor (String, String?, LocalVoiceTrace?) async throws -> VoiceWorkspaceSyncPayload = { text, context, trace in
             guard #available(iOS 26.0, *) else { throw LocalVoiceError(message: loc("LocalNeedsOS")) }
             return try await AppleExpenseInterpreter.interpret(text, context: context, trace: trace)
         }) {
        self.processingTimeout = processingTimeout; self.processor = processor
    }

    private func createTrace(id: UUID) -> LocalVoiceTrace {
        var variant = "OS26 system model"
        if #available(iOS 27.0, *) { variant = SystemLanguageModel.default.variant.displayName }
        let trace = LocalVoiceTrace(language: Self.locale.identifier, modelVariant: variant,
            availability: String(describing: LocalVoiceAvailability.current), referenceDate: VoiceModeViewModel.todayISOString())
        trace.onUpdate = { [weak self] value in
            guard let self, self.identity == id else { return }
            self.onEvent?(.localDiagnostic(value))
        }
        return trace
    }


    func connect(workspaceContext: String?) async throws {
        disconnect()
        let id = identity
        context = workspaceContext
        trace = createTrace(id: id)
        trace?.begin("availability")
        guard LocalVoiceAvailability.current == .available else {
            trace?.failed(.init(.unavailable, reason: "model-availability"))
            throw LocalVoiceError(message: LocalVoiceAvailability.current.message)
        }
        trace?.begin("speech-permission")
        let speechPermission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        try checkIdentity(id)
        guard speechPermission == .authorized else { trace?.failed(.init(.speech, reason: "speech-permission")); throw LocalVoiceError(message: loc("LocalSpeechPermission")) }
        trace?.begin("microphone-permission")
        let micPermission = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        try checkIdentity(id)
        guard micPermission else { trace?.failed(.init(.speech, reason: "microphone-permission")); throw LocalVoiceError(message: loc("LocalMicPermission")) }
        do { try startRecording(id: id) }
        catch { trace?.failed(.init(.speech, reason: "capture-start")); disconnect(); throw error }
    }

    private func checkIdentity(_ id: UUID) throws {
        try Task.checkCancellation()
        guard identity == id else { throw CancellationError() }
    }

    private func startRecording(id: UUID) throws {
        guard let recognizer = SFSpeechRecognizer(locale: Self.locale),
              recognizer.supportsOnDeviceRecognition else {
            throw LocalVoiceError(message: loc("LocalSpeechUnavailable"))
        }
        trace?.begin("speech")
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        // Apple only honors this flag after supportsOnDeviceRecognition was checked.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setActive(true)
        ownsAudioSession = true
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw LocalVoiceError(message: loc("LocalMicPermission"))
        }
        self.engine = engine
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.identity == id, !self.generating else { return }
                if let text {
                    self.transcript = text
                    self.endpoint.updateTranscript(text, at: ProcessInfo.processInfo.systemUptime)
                    self.onEvent?(.localEndpointProgress(self.endpoint.indicatorProgress(at: ProcessInfo.processInfo.systemUptime)))
                    self.onEvent?(.localTranscript(text))
                }
                switch LocalRecognitionCompletion.action(final: final, failed: failed, finishing: self.finishing) {
                case .complete:
                    self.processTurn(id: id, completion: final ? "asr-final" : "finishing-recognition-error")
                case .fail:
                    self.fail(loc("LocalRecognitionFailed"), issue: .init(.speech))
                case .wait: break
                }
            }
        }
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let count = Int(buffer.frameLength)
            let level: Double
            if let channel = buffer.floatChannelData?[0], count > 0 {
                var sum: Float = 0
                for index in 0..<count { sum += channel[index] * channel[index] }
                level = min(1, Double(sqrt(sum / Float(count))) * 12)
            } else { level = 0 }
            Task { @MainActor [weak self] in
                guard let self, self.identity == id, !self.finishing, !self.generating else { return }
                self.onEvent?(.microphoneLevel(level))
                self.endpoint.observeLevel(level, at: ProcessInfo.processInfo.systemUptime)
                if level >= 0.10 { self.onEvent?(.localEndpointProgress(0)) }
            }
        }
        engine.prepare()
        try engine.start()
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification, AVAudioSession.mediaServicesWereLostNotification,
                     .AVAudioEngineConfigurationChange, UIApplication.didEnterBackgroundNotification] {
            // Scope engine notifications to this recorder. Session notifications
            // are global and can include delayed category changes from startup.
            let object: Any? = name == .AVAudioEngineConfigurationChange ? engine : nil
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] notification in
                let shouldInterrupt = LocalRecordingLifecycle.shouldInterrupt(notification)
                Task { @MainActor [weak self] in
                    guard shouldInterrupt, let self, self.identity == id, self.engine != nil else { return }
                    self.fail(loc("VoiceAudioInterrupted"), issue: .init(.interrupted))
                }
            })
        }
        onEvent?(.microphoneStarted)
        timer = Task { [weak self] in
            let started = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self, self.identity == id else { return }
                let now = ProcessInfo.processInfo.systemUptime
                self.onEvent?(.localEndpointProgress(self.endpoint.indicatorProgress(at: now)))
                if self.endpoint.shouldFinish(at: now) || now - started >= 50 {
                    self.finishTurn(reason: now - started >= 50 ? "recording-limit" : "quiet-endpoint")
                    return
                }
            }
        }
    }

    func finishTurn() { finishTurn(reason: "manual-stop") }

    private func finishTurn(reason: String) {
        captureEndReason = reason
        guard engine != nil, !finishing, !generating else { return }
        finishing = true
        timer?.cancel()
        stopMicrophone()
        onEvent?(.listeningStopped)
        request?.endAudio()
        let id = identity
        // Recognition may never deliver a final callback after an interruption.
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.identity == id else { return }
            self.processTurn(id: id, completion: "recognition-fallback")
        }
    }

    private func processTurn(id: UUID, completion: String) {
        guard identity == id, !generating else { return }
        stopMicrophone()
        recognition?.cancel(); recognition = nil; request = nil
        processRecognizedText(transcript, workspaceContext: context,
            completion: finishing ? "\(captureEndReason)/\(completion)" : completion)
    }

    /// Production ASR boundary. Also exercised without a microphone in service tests.
    func processRecognizedText(_ transcript: String, workspaceContext: String?, completion: String = "asr-final") {
        guard !generating else { return }
        let id = identity
        generating = true
        timer?.cancel()
        if trace == nil { trace = createTrace(id: id) }
        trace?.captureEnded(completion)
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { trace?.completed(); onEvent?(.localTurnReady); return }
        guard text.count <= 1_500, (workspaceContext?.count ?? 0) <= 7_000 else {
            fail(loc("LocalTooMuchContext"), issue: .init(.context, reason: "app-input-limit")); return
        }
        onEvent?(.responseStarted(id: id.uuidString, isAppGenerated: false))
        let currentTrace = trace
        generation = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.processor(text, workspaceContext, currentTrace)
                try self.checkIdentity(id)
                self.timer?.cancel()
                currentTrace?.completed()
                var result = payload; result.responseID = id.uuidString
                self.onEvent?(.workspaceSync(result))
                self.onEvent?(.responseFinished(id: id.uuidString))
                self.onEvent?(.localTurnReady)
            } catch {
                guard !Task.isCancelled, self.identity == id else { return }
                let issue: LocalVoiceIssue
                if #available(iOS 26.0, *) { issue = LocalVoiceIssue.classify(error) }
                else { issue = .init(.unavailable) }
                self.fail((error as? LocalVoiceError)?.message ?? issue.category.message, issue: issue)
            }
        }
        timer = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.processingTimeout)
            guard !Task.isCancelled, self.identity == id else { return }
            self.fail(loc("LocalModelTimeout"), issue: .init(.timeout, reason: "processing-deadline"))
        }
    }

    private func stopMicrophone() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        if let engine {
            self.engine = nil
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
        onEvent?(.microphoneStopped)
    }

    private func fail(_ message: String, issue: LocalVoiceIssue? = nil) {
        trace?.failed(issue ?? .init(.unknown, reason: "capture-or-permission"))
        disconnect()
        onEvent?(.error(message))
    }

    func disconnect() {
        identity = UUID()
        timer?.cancel(); timer = nil
        generation?.cancel(); generation = nil
        stopMicrophone()
        recognition?.cancel(); recognition = nil
        request = nil
        recognizer = nil
        transcript = ""
        context = nil
        trace = nil; captureEndReason = "asr-final"
        finishing = false
        generating = false
        endpoint = LocalSpeechEndpoint()
    }

    // Each new turn receives the current app workspace. Deletions during generation
    // are filtered by the view model's tombstones before any drafts are displayed.
    func sendWorkspaceNote(_ text: String) {}
}

/// Requires both quiet audio and stable recognition. Partial results replace the
/// same phrase; they are never independently submitted to the expense model.
struct LocalSpeechEndpoint {
    private var text = ""
    private var changedAt: TimeInterval = 0
    private var speechAt: TimeInterval = 0

    mutating func updateTranscript(_ value: String, at time: TimeInterval) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != text { text = trimmed; changedAt = time }
    }

    mutating func observeLevel(_ level: Double, at time: TimeInterval) {
        if level >= 0.10 { speechAt = time }
    }

    func shouldFinish(at time: TimeInterval) -> Bool {
        progress(at: time) >= 1
    }

    // Presentation waits for a settled pause; the capture endpoint is unchanged.
    func indicatorProgress(at time: TimeInterval) -> Double {
        guard time - max(changedAt, speechAt) >= 0.65 else { return 0 }
        return progress(at: time)
    }

    func progress(at time: TimeInterval) -> Double {
        guard !text.isEmpty else { return 0 }
        let lastWord = text.lowercased().split(whereSeparator: { !$0.isLetter }).last.map(String.init) ?? ""
        // A conjunction or preposition often precedes another item/value. Give
        // these sentence pauses more room without waiting indefinitely.
        let grace: TimeInterval = ["and", "und", "for", "für", "with", "mit", "of", "von", "was", "war"].contains(lastWord) ? 4.5 : 2.2
        return min(1, max(0, (time - max(changedAt, speechAt)) / grace))
    }
}

/// Category changes are expected when activating/deactivating our microphone.
/// An interruption ending is permission to resume, not a new interruption.
enum LocalRecordingLifecycle {
    static func shouldInterrupt(_ notification: Notification) -> Bool {
        notification.name == UIApplication.didEnterBackgroundNotification ||
            VoiceAudioLifecycleEvent(notification: notification) != nil
    }
}

/// endAudio can return an error instead of a final result, especially for silence.
/// Only an intentional finish consumes that callback as normal completion.
enum LocalRecognitionCompletion {
    enum Action: Equatable { case wait, complete, fail }
    static func action(final: Bool, failed: Bool, finishing: Bool) -> Action {
        if final || (failed && finishing) { return .complete }
        return failed ? .fail : .wait
    }
}

/// Keep the last arc while it fades; never animate a timer reset backwards.
struct LocalEndpointIndicator {
    private(set) var progress: Double = 0
    private(set) var isVisible = false
    mutating func update(_ value: Double) {
        guard value.isFinite, value > 0 else { isVisible = false; return }
        progress = min(1, value)
        isVisible = true
    }
}
