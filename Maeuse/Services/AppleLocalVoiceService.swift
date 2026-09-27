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

    func connect(workspaceContext: String?) async throws {
        disconnect()
        let id = identity
        context = workspaceContext
        guard LocalVoiceAvailability.current == .available else {
            throw LocalVoiceError(message: LocalVoiceAvailability.current.message)
        }
        let speechPermission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        try checkIdentity(id)
        guard speechPermission == .authorized else { throw LocalVoiceError(message: loc("LocalSpeechPermission")) }
        let micPermission = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        try checkIdentity(id)
        guard micPermission else { throw LocalVoiceError(message: loc("LocalMicPermission")) }
        do { try startRecording(id: id) }
        catch { disconnect(); throw error }
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
                    self.onEvent?(.localTranscript(text))
                }
                if final || (failed && self.finishing && !self.transcript.isEmpty) {
                    self.processTurn(id: id)
                } else if failed {
                    self.fail(loc("LocalRecognitionFailed"))
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
            }
        }
        engine.prepare()
        try engine.start()
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification, AVAudioSession.mediaServicesWereLostNotification,
                     .AVAudioEngineConfigurationChange, UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.identity == id, self.engine != nil else { return }
                    self.fail(loc("VoiceAudioInterrupted"))
                }
            })
        }
        onEvent?(.microphoneStarted)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(50))
            guard !Task.isCancelled, let self, self.identity == id else { return }
            self.finishTurn()
        }
    }

    func finishTurn() {
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
            self.processTurn(id: id)
        }
    }

    private func processTurn(id: UUID) {
        guard !generating else { return }
        generating = true
        timer?.cancel()
        stopMicrophone()
        recognition?.cancel()
        recognition = nil
        request = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { fail(loc("LocalNoSpeech")); return }
        guard text.count <= 1_500, (context?.count ?? 0) <= 7_000 else {
            fail(loc("LocalTooMuchContext")); return
        }
        onEvent?(.responseStarted(id: id.uuidString, isAppGenerated: false))
        generation = Task { [weak self] in
            guard let self else { return }
            do {
                guard #available(iOS 26.0, *) else { throw LocalVoiceError(message: loc("LocalNeedsOS")) }
                let payload = try await AppleExpenseInterpreter.interpret(text, context: self.context)
                try self.checkIdentity(id)
                self.timer?.cancel()
                var result = payload
                result.responseID = id.uuidString
                self.onEvent?(.workspaceSync(result))
                self.onEvent?(.responseFinished(id: id.uuidString))
                self.onEvent?(.localTurnReady)
            } catch {
                guard !Task.isCancelled, self.identity == id else { return }
                self.fail((error as? LocalVoiceError)?.message ?? loc("LocalGenerationFailed"))
            }
        }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self, self.identity == id else { return }
            self.fail(loc("LocalGenerationFailed"))
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

    private func fail(_ message: String) {
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
        finishing = false
        generating = false
    }

    // Each new turn receives the current app workspace. Deletions during generation
    // are filtered by the view model's tombstones before any drafts are displayed.
    func sendWorkspaceNote(_ text: String) {}
}
