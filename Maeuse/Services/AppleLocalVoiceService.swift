import AVFoundation
import Foundation
import FoundationModels
@preconcurrency import Speech
import UIKit

enum LocalVoiceAvailability: Equatable {
    case available, needsOS, deviceNotEligible, intelligenceDisabled, modelNotReady, unsupportedLanguage, speechUnavailable
    /// The on-device speech model for the app language is not installed yet. It downloads
    /// from Settings or automatically on the first capture; capture then works offline.
    case speechModelMissing

    var message: String {
        switch self {
        case .available: return loc("LocalAvailable")
        case .needsOS: return loc("LocalNeedsOS")
        case .deviceNotEligible: return loc("LocalDeviceUnsupported")
        case .intelligenceDisabled: return loc("LocalIntelligenceDisabled")
        case .modelNotReady: return loc("LocalModelNotReady")
        case .unsupportedLanguage: return loc("LocalLanguageUnsupported")
        case .speechUnavailable: return loc("LocalSpeechUnavailable")
        case .speechModelMissing: return loc("LocalSpeechModelMissing")
        }
    }

    /// A missing speech model is downloadable, so it does not block enabling capture.
    var allowsCapture: Bool { self == .available || self == .speechModelMissing }

    /// Synchronous checks only. Speech assets are asynchronous; see `resolved()`.
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
        return .available
    }

    /// `current` plus the on-device speech model state for the app language.
    @MainActor static func resolved() async -> Self {
        let base = current
        guard base == .available, #available(iOS 26.0, *) else { return base }
        switch await LocalSpeechTranscription.assetStatus(for: AppleLocalVoiceService.locale) {
        case .installed: return .available
        case .supported, .downloading: return .speechModelMissing
        case .unsupported: return .speechUnavailable
        @unknown default: return .speechUnavailable
        }
    }

    @MainActor static func installSpeechModel() async throws {
        guard #available(iOS 26.0, *) else { throw LocalVoiceError(message: loc("LocalNeedsOS")) }
        try await LocalSpeechTranscription.installAssets(for: AppleLocalVoiceService.locale)
    }
}

struct LocalVoiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// iOS 26 on-device transcription: `SpeechTranscriber` (or `DictationTranscriber` where the
/// newer model is unavailable) analyzing microphone buffers through `SpeechAnalyzer`.
/// Partial ("volatile") results drive the endpoint; finalized results build the phrase.
@available(iOS 26.0, *)
@MainActor
final class LocalSpeechTranscription {
    enum Failure: Error { case unsupportedLocale, unavailable }

    private let analyzer: SpeechAnalyzer
    let feeder: LocalSpeechAudioFeeder
    private var results: Task<Void, Never>?
    private var finalized = ""
    private var volatile = ""

    private init(analyzer: SpeechAnalyzer, feeder: LocalSpeechAudioFeeder) {
        self.analyzer = analyzer; self.feeder = feeder
    }

    private static func module(for locale: Locale) -> any SpeechModule {
        SpeechTranscriber.isAvailable
            ? SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            : DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
    }

    private static func supportedLocale(for locale: Locale) async -> Locale? {
        SpeechTranscriber.isAvailable
            ? await SpeechTranscriber.supportedLocale(equivalentTo: locale)
            : await DictationTranscriber.supportedLocale(equivalentTo: locale)
    }

    static func assetStatus(for locale: Locale) async -> AssetInventory.Status {
        guard let supported = await supportedLocale(for: locale) else { return .unsupported }
        return await AssetInventory.status(forModules: [module(for: supported)])
    }

    /// Downloads the language model once; it is reused offline afterwards.
    static func installAssets(for locale: Locale) async throws {
        guard let supported = await supportedLocale(for: locale) else { throw Failure.unsupportedLocale }
        try await installAssets(for: module(for: supported))
    }

    private static func installAssets(for module: any SpeechModule) async throws {
        switch await AssetInventory.status(forModules: [module]) {
        case .installed: return
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        case .unsupported: throw Failure.unavailable
        @unknown default: throw Failure.unavailable
        }
    }

    /// Prepares the model (downloading it on first use) and starts analysis. Audio arrives
    /// later through `feeder`; `onTranscript` receives the whole phrase so far.
    static func start(locale: Locale,
                      onTranscript: @escaping @MainActor (String) -> Void,
                      onEnd: @escaping @MainActor (_ failed: Bool) -> Void) async throws -> LocalSpeechTranscription {
        guard let supported = await supportedLocale(for: locale) else { throw Failure.unsupportedLocale }
        let module = module(for: supported)
        try await installAssets(for: module)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw Failure.unavailable }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)
        let transcription = LocalSpeechTranscription(analyzer: analyzer,
            feeder: LocalSpeechAudioFeeder(format: format, continuation: continuation))
        transcription.consume(module, onTranscript: onTranscript, onEnd: onEnd)
        do { try await analyzer.start(inputSequence: stream) }
        catch { transcription.cancel(); throw error }
        return transcription
    }

    private func consume(_ module: any SpeechModule,
                         onTranscript: @escaping @MainActor (String) -> Void,
                         onEnd: @escaping @MainActor (Bool) -> Void) {
        results = Task { [weak self] in
            do {
                if let transcriber = module as? SpeechTranscriber {
                    for try await result in transcriber.results {
                        self?.receive(String(result.text.characters), isFinal: result.isFinal, onTranscript)
                    }
                } else if let dictation = module as? DictationTranscriber {
                    for try await result in dictation.results {
                        self?.receive(String(result.text.characters), isFinal: result.isFinal, onTranscript)
                    }
                }
                if !Task.isCancelled { onEnd(false) }
            } catch {
                if !Task.isCancelled { onEnd(true) }
            }
        }
    }

    private func receive(_ text: String, isFinal: Bool, _ onTranscript: @MainActor (String) -> Void) {
        // A volatile result replaces the previous guess for the same audio; a final result
        // is appended and never revised.
        if isFinal { finalized += text; volatile = "" } else { volatile = text }
        onTranscript(finalized + volatile)
    }

    /// No more audio: finalize what was heard. The results sequence then ends.
    func finishInput() {
        feeder.finish()
        let analyzer = analyzer
        Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
    }

    func cancel() {
        results?.cancel(); results = nil
        feeder.finish()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}

/// Converts microphone buffers to the analyzer's format and yields them. It is called only
/// from the audio engine's tap thread; the stream continuation itself is thread-safe.
@available(iOS 26.0, *)
final class LocalSpeechAudioFeeder: @unchecked Sendable {
    private let format: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?

    init(format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.format = format; self.continuation = continuation
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    func finish() { continuation.finish() }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error || output.frameLength == 0 ? nil : output
    }
}

/// Apple on-device speech analysis (offline once the language model is installed)
/// followed by the on-device system model.
/// This service has no credentials, network client, or reference to the cloud service.
@MainActor
final class AppleLocalVoiceService: VoiceSessionService {
    var onEvent: ((RealtimeVoiceServiceEvent) -> Void)?
    private static let audioSessionQueue = DispatchQueue(label: "maeuse.local.audio-session", qos: .userInitiated)
    static var locale: Locale {
        Locale(identifier: LanguageManager.shared.activeLanguageCode == "de" ? "de-DE" : "en-US")
    }

    private var engine: AVAudioEngine?
    /// A `LocalSpeechTranscription`; stored untyped because the app still deploys to iOS 17.
    private var transcription: AnyObject?
    @available(iOS 26.0, *)
    private var speech: LocalSpeechTranscription? { transcription as? LocalSpeechTranscription }
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
        do { try await startRecording(id: id) }
        catch { trace?.failed(.init(.speech, reason: "capture-start")); disconnect(); throw error }
    }

    private func checkIdentity(_ id: UUID) throws {
        try Task.checkCancellation()
        guard identity == id else { throw CancellationError() }
    }

    private func startRecording(id: UUID) async throws {
        guard #available(iOS 26.0, *) else { throw LocalVoiceError(message: loc("LocalNeedsOS")) }
        // Prepare the speech model before the microphone: the first use may download it.
        trace?.begin("speech-model")
        let speech: LocalSpeechTranscription
        do {
            speech = try await LocalSpeechTranscription.start(locale: Self.locale,
                onTranscript: { [weak self] text in self?.receiveTranscript(text, id: id) },
                onEnd: { [weak self] failed in self?.recognitionEnded(failed: failed, id: id) })
        } catch is CancellationError {
            throw CancellationError()
        } catch is LocalSpeechTranscription.Failure {
            throw LocalVoiceError(message: loc("LocalSpeechUnavailable"))
        } catch {
            throw LocalVoiceError(message: loc("LocalSpeechModelPreparationFailed"))
        }
        transcription = speech
        try checkIdentity(id)
        trace?.begin("speech")
        // Serialized with the asynchronous deactivation of the previous turn, so a late
        // deactivation can never stop this recording.
        try Self.audioSessionQueue.sync {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            // Otherwise iOS mutes the "listening again" haptic while the microphone records.
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true)
        }
        ownsAudioSession = true
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw LocalVoiceError(message: loc("LocalMicPermission"))
        }
        self.engine = engine
        input.installTap(onBus: 0, bufferSize: 2_048, format: format,
                         block: Self.tap(feeding: speech.feeder) { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self, self.identity == id, !self.finishing, !self.generating else { return }
                self.onEvent?(.microphoneLevel(level))
                self.endpoint.observeLevel(level, at: ProcessInfo.processInfo.systemUptime)
                if level >= 0.10 { self.onEvent?(.localEndpointProgress(0)) }
            }
        })
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

    /// Built outside the main actor: the engine calls it on its audio thread.
    @available(iOS 26.0, *)
    private nonisolated static func tap(feeding feeder: LocalSpeechAudioFeeder,
                                        level report: @escaping @Sendable (Double) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            feeder.append(buffer)
            let count = Int(buffer.frameLength)
            var level = 0.0
            if let channel = buffer.floatChannelData?[0], count > 0 {
                var sum: Float = 0
                for index in 0..<count { sum += channel[index] * channel[index] }
                level = min(1, Double(sqrt(sum / Float(count))) * 12)
            }
            report(level)
        }
    }

    private func receiveTranscript(_ text: String, id: UUID) {
        guard identity == id, !generating else { return }
        transcript = text
        let now = ProcessInfo.processInfo.systemUptime
        endpoint.updateTranscript(text, at: now)
        onEvent?(.localEndpointProgress(endpoint.indicatorProgress(at: now)))
        onEvent?(.localTranscript(text))
    }

    /// The results sequence ended: normally after finishing input, or with an error.
    private func recognitionEnded(failed: Bool, id: UUID) {
        guard identity == id, !generating else { return }
        switch LocalRecognitionCompletion.action(final: !failed, failed: failed, finishing: finishing) {
        case .complete: processTurn(id: id, completion: failed ? "finishing-recognition-error" : "asr-final")
        case .fail: fail(loc("LocalRecognitionFailed"), issue: .init(.speech))
        case .wait: break
        }
    }

    private func cancelTranscription() {
        if #available(iOS 26.0, *) { speech?.cancel() }
        transcription = nil
    }

    func finishTurn() { finishTurn(reason: "manual-stop") }

    private func finishTurn(reason: String) {
        captureEndReason = reason
        guard engine != nil, !finishing, !generating else { return }
        finishing = true
        timer?.cancel()
        stopMicrophone()
        onEvent?(.listeningStopped)
        if #available(iOS 26.0, *) { speech?.finishInput() }
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
        cancelTranscription()
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
        guard !text.isEmpty else {
            trace?.completed()
            // Nobody spoke for the whole recording: pause instead of restarting the microphone forever.
            if captureEndReason == "recording-limit" { onEvent?(.localNoSpeech) }
            onEvent?(.localTurnReady)
            return
        }
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
                let message: String
                if case VoiceWorkspaceDomain.InvalidChange.tooManyDrafts = error { message = loc("LocalDraftLimit") }
                else { message = (error as? LocalVoiceError)?.message ?? issue.category.message }
                self.fail(message, issue: issue)
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
            // Deactivation can block for a noticeable time; keep it off the main thread.
            Self.audioSessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
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
        cancelTranscription()
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
