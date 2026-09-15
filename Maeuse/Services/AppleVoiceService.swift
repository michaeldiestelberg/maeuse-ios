import AVFoundation
import CoreMedia
import Foundation
import Speech

@MainActor
protocol VoiceCaptureService: AnyObject {
    func connect() async throws
    func disconnect()
    func updateDrafts(_ drafts: [VoiceExpenseDraft])
    func sendWorkspaceNote(_ note: String)
}

extension RealtimeVoiceService: VoiceCaptureService {
    func updateDrafts(_ drafts: [VoiceExpenseDraft]) {}
}

/// Final speech segments can precede the end of an utterance. Collect them until a pause.
struct AppleSpeechTurnBuffer {
    private var segments: [Double: (end: Double, text: String)] = [:]
    private var consumedThrough = -Double.infinity

    mutating func appendFinal(text: String, start: Double, end: Double) {
        guard start.isFinite, end.isFinite, end > consumedThrough else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { segments[start] = (end, text) }
    }

    mutating func takeUtterance() -> String {
        let ordered = segments.sorted { $0.key < $1.key }
        if let end = ordered.map({ $0.value.end }).max() { consumedThrough = max(consumedThrough, end) }
        segments.removeAll()
        return ordered.map { $0.value.text }.joined(separator: " ")
    }
}

@available(iOS 26, *)
@MainActor
final class AppleVoiceService: VoiceCaptureService {
    private let onEvent: (RealtimeVoiceServiceEvent) -> Void
    private let locale: Locale
    private let interpreter: AppleWorkspaceInterpreter
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var tasks: [Task<Void, Never>] = []
    private var pauseTask: Task<Void, Never>?
    private var requests: AppleVoiceRequestQueue?
    private var observers: [NSObjectProtocol] = []
    private var running = false
    private var speaking = false
    private var hasUnprocessedSpeech = false
    private var turnBuffer = AppleSpeechTurnBuffer()

    init(locale: Locale, usePrivateCloudCompute: Bool, onEvent: @escaping (RealtimeVoiceServiceEvent) -> Void) {
        self.locale = locale
        self.interpreter = AppleWorkspaceInterpreter(usePrivateCloudCompute: usePrivateCloudCompute)
        self.onEvent = onEvent
    }

    func connect() async throws {
        let availability = await AppleVoiceAvailability.check(locale: locale)
        guard availability.canStart else { throw AppleVoiceError.message(availability.messageKey) }
        guard !interpreter.usePrivateCloudCompute || AppleVoiceAvailability.privateCloudComputeEnabledInBuild else {
            throw AppleVoiceError.message("PCCAccessPending")
        }
        guard await AVAudioApplication.requestRecordPermission() else { throw AppleVoiceError.message("AppleMicrophoneDenied") }
        try Task.checkCancellation()
        guard let speechLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AppleVoiceError.message("AppleLanguageUnsupported")
        }
        try await AssetInventory.reserve(locale: speechLocale)
        let transcriber = SpeechTranscriber(locale: speechLocale, preset: .progressiveTranscription)
        let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: true)
        let modules: [any SpeechModule] = [transcriber, detector]
        if await AssetInventory.status(forModules: modules) != .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            onEvent(.connectionStatus(loc("AppleDownloadingAssets")))
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw AppleVoiceError.message("AppleAudioUnavailable")
        }
        let analyzer = SpeechAnalyzer(modules: modules)
        self.analyzer = analyzer
        do {
            try await analyzer.prepareToAnalyze(in: format)
            try Task.checkCancellation()
            try await activateAudioSession()
            try Task.checkCancellation()
            let engine = AVAudioEngine()
            let source = engine.inputNode.outputFormat(forBus: 0)
            guard source.sampleRate > 0, source.channelCount > 0 else { throw AppleVoiceError.message("AppleAudioUnavailable") }
            let stream = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(100))
            self.input = stream.continuation
            let converter = try AppleAudioInputConverter(source: source, target: format, continuation: stream.continuation) { [weak self] level, failed in
                Task { @MainActor [weak self] in
                    guard let self, self.running else { return }
                    if failed { self.fail(AppleVoiceError.message("AppleAudioUnavailable")) }
                    else { self.onEvent(.microphoneLevel(level)) }
                }
            }
            engine.inputNode.installTap(onBus: 0, bufferSize: 1_024, format: source) { buffer, _ in
                converter.accept(buffer)
            }
            self.engine = engine
            running = true
            let interpreter = self.interpreter
            let locale = self.locale
            requests = AppleVoiceRequestQueue(interpret: { text, drafts in
                try await interpreter.interpret(text, drafts: drafts, locale: locale,
                    todayISO: VoiceModeViewModel.todayISOString())
            }, onEvent: onEvent, onFailure: { [weak self] error in self?.fail(error) })
            tasks.append(Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self, self.running, !Task.isCancelled else { return }
                        self.hasUnprocessedSpeech = true
                        self.onEvent(.recognitionPending(true))
                        if result.isFinal {
                            self.turnBuffer.appendFinal(text: String(result.text.characters),
                                start: result.range.start.seconds, end: CMTimeRangeGetEnd(result.range).seconds)
                        }
                        if !self.speaking { self.schedulePause() }
                    }
                } catch { if !Task.isCancelled { self?.fail(error) } }
            })
            tasks.append(Task { [weak self] in
                do {
                    for try await result in detector.results {
                        guard let self, self.running, !Task.isCancelled else { return }
                        let wasSpeaking = self.speaking
                        self.speaking = result.speechDetected
                        self.onEvent(.speechActivity(result.speechDetected))
                        if result.speechDetected {
                            self.hasUnprocessedSpeech = true
                            self.onEvent(.recognitionPending(true))
                            self.pauseTask?.cancel()
                        } else if wasSpeaking {
                            self.schedulePause()
                        }
                    }
                } catch { if !Task.isCancelled { self?.fail(error) } }
            })
            tasks.append(Task { [weak self] in
                do { try await analyzer.start(inputSequence: stream.stream) }
                catch { if !Task.isCancelled { self?.fail(error) } }
            })
            observeAudioInterruptions()
            engine.prepare()
            try engine.start()
            onEvent(.connected)
            onEvent(.microphoneStarted)
        } catch {
            disconnect()
            throw error
        }
    }

    private func schedulePause() {
        pauseTask?.cancel()
        pauseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(900))
                guard let self, self.running, !self.speaking, self.hasUnprocessedSpeech else { return }
                // Finalize provisional words before interpreting the whole utterance.
                try await self.analyzer?.finalize(through: nil)
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                guard self.running, !self.speaking else { return }
                let text = self.turnBuffer.takeUtterance()
                self.hasUnprocessedSpeech = false
                if !text.isEmpty {
                    try self.requests?.enqueue(text)
                }
                self.onEvent(.recognitionPending(false))
            } catch {
                if !Task.isCancelled { self?.fail(error) }
            }
        }
    }

    func updateDrafts(_ drafts: [VoiceExpenseDraft]) {
        requests?.updateDrafts(drafts)
    }

    func sendWorkspaceNote(_ note: String) { /* App-owned drafts are the canonical context. */ }

    func disconnect() {
        running = false
        pauseTask?.cancel()
        requests?.cancel()
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        input?.finish()
        input = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        requests = nil
        turnBuffer = AppleSpeechTurnBuffer()
        RealtimeVoiceService.audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        onEvent(.microphoneStopped)
    }

    private func fail(_ error: Error) {
        guard running else { return }
        disconnect()
        // Do not put framework errors (which may contain recognized text) into logs/history.
        onEvent(.error((error as? AppleVoiceError)?.localizedDescription ?? loc("AppleProcessingFailed")))
    }

    private func observeAudioInterruptions() {
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                if notification.name == AVAudioSession.routeChangeNotification {
                    let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
                    guard reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
                }
                if notification.name == AVAudioSession.interruptionNotification {
                    guard notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue else { return }
                }
                Task { @MainActor [weak self] in self?.fail(AppleVoiceError.message("AppleAudioInterrupted")) }
            })
        }
    }

    private func activateAudioSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            RealtimeVoiceService.audioSessionQueue.async {
                do {
                    let audio = AVAudioSession.sharedInstance()
                    try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try audio.setActive(true)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

/// AVAudioEngine invokes its tap serially. Convert/copy before its buffer is reused.
@available(iOS 26, *)
private final class AppleAudioInputConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let report: @Sendable (Double, Bool) -> Void
    private var lastMeter = Date.distantPast

    init(source: AVAudioFormat, target: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation,
         report: @escaping @Sendable (Double, Bool) -> Void) throws {
        guard let converter = AVAudioConverter(from: source, to: target) else { throw AppleVoiceError.message("AppleAudioUnavailable") }
        self.converter = converter
        self.target = target
        self.continuation = continuation
        self.report = report
    }

    func accept(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { report(0, true); return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { report(0, true); return }
        if output.frameLength > 0 {
            if case .dropped = continuation.yield(AnalyzerInput(buffer: output)) { report(0, true) }
        }
        if Date().timeIntervalSince(lastMeter) >= 0.08 {
            lastMeter = Date()
            var level = 0.0
            if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                var sum = 0.0
                for index in 0..<Int(buffer.frameLength) { sum += Double(samples[index] * samples[index]) }
                level = min(1, sqrt(sum / Double(buffer.frameLength)) * 8)
            }
            report(level, false)
        }
    }
}
