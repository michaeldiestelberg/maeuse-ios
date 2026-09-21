import AVFoundation
import Foundation
import OSLog

@MainActor
protocol RealtimeVoiceServiceDelegate: AnyObject {
    func realtimeVoiceService(_ service: RealtimeVoiceService, didReceive event: RealtimeVoiceServiceEvent)
}

enum RealtimeVoiceServiceEvent {
    case connected
    case disconnected
    case microphoneReady
    case microphoneStarted
    case microphoneStopped
    case microphoneLevel(Double)
    case listeningStarted
    case listeningStopped
    case responseStarted(id: String, isAppGenerated: Bool)
    case responseFinished(id: String)
    case workspaceSync(VoiceWorkspaceSyncPayload)
    case assistantText(String)
    case assistantTextDelta(String)
    case error(String)
}

/// Transport, parser, and lifecycle state have one owner. Every callback carries
/// the connection identity so cancellation also invalidates already-queued work.
@MainActor
final class RealtimeVoiceService: NSObject {
    private weak var delegate: RealtimeVoiceServiceDelegate?
    private let logger = Logger(subsystem: "com.michaeldiestelberg.maeuse", category: "RealtimeVoice")
    private let clientSecretService = OpenAIRealtimeClientSecretService()
    private static let audioSessionQueue = DispatchQueue(label: "maeuse.realtime.audio-session", qos: .userInitiated)
    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketOpenContinuation: CheckedContinuation<Void, Error>?
    private var audioEngine: AVAudioEngine?
    private var audioObservers: [NSObjectProtocol] = []
    private var parser = RealtimeServerEventParser()
    private var isDisconnecting = false
    private var lastLevelEmit = Date.distantPast
    private(set) var connectionID = UUID()

    func setDelegate(_ delegate: RealtimeVoiceServiceDelegate?) { self.delegate = delegate }

    func connect(workspaceContext: String? = nil) async throws {
        try Task.checkCancellation()
        disconnect()
        isDisconnecting = false
        let id = connectionID
        do {
            guard let key = try OpenAIAPIKeyStore.shared.readAPIKey() else { throw RealtimeVoiceError.missingAPIKey }
            let credential = try await clientSecretService.createClientSecret(apiKey: key)
            try checkConnection(id)
            try await connectWebSocket(credential: credential.value)
            try checkConnection(id)
            try await sendAsync(["type": "session.update", "session": RealtimeSessionConfiguration.webSocketSession()])
            if let workspaceContext { try await sendAsync(Self.workspaceNoteEvent(workspaceContext)) }
            try checkConnection(id)
            try await prepareAudioSession()
            try checkConnection(id)
            try startAudioCapture(connectionID: id)
        } catch {
            if connectionID == id { disconnect() }
            // A cancelled activation may finish after disconnect. Queue cleanup
            // before the view model starts the next serialized connection attempt.
            else { deactivateAudioSession() }
            throw error
        }
    }

    private func checkConnection(_ id: UUID) throws {
        try Task.checkCancellation()
        guard id == connectionID, !isDisconnecting else { throw CancellationError() }
    }

    func disconnect() {
        connectionID = UUID()
        isDisconnecting = true
        for observer in audioObservers { NotificationCenter.default.removeObserver(observer) }
        audioObservers = []
        stopAudioCapture()
        deactivateAudioSession()
        let continuation = webSocketOpenContinuation
        webSocketOpenContinuation = nil
        continuation?.resume(throwing: RealtimeVoiceError.disconnected)
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        parser = RealtimeServerEventParser()
        lastLevelEmit = .distantPast
    }

    static func workspaceNoteEvent(_ text: String) -> [String: Any] {
        ["type": "conversation.item.create", "item": ["type": "message", "role": "user",
            "content": [["type": "input_text", "text": text]]]]
    }

    func sendWorkspaceNote(_ text: String) {
        // The local action has already updated the UI. Record it for the next
        // spoken turn without attempting a competing response.create.
        send(Self.workspaceNoteEvent(text))
    }

    private func connectWebSocket(credential: String) async throws {
        guard !credential.isEmpty else { throw OpenAIRealtimeClientSecretError.decodeFailed }
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: RealtimeSessionConfiguration.model)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        urlSession = session
        webSocketTask = task
        try await withCheckedThrowingContinuation { continuation in
            webSocketOpenContinuation = continuation
            task.resume()
        }
    }

    private func prepareAudioSession() async throws {
        let permitted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard permitted else { throw RealtimeVoiceError.microphoneDenied }
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.audioSessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try session.setPreferredIOBufferDuration(0.02)
                    try session.setActive(true)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func deactivateAudioSession() {
        Self.audioSessionQueue.async { [logger] in
            do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
            catch { logger.warning("Could not deactivate audio: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private func startAudioCapture(connectionID id: UUID) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw RealtimeVoiceError.noMicrophoneInput }
        let processor = try VoiceAudioProcessor(inputFormat: format)
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            guard let data = processor.convert(buffer) else { return }
            // Dispatch preserves audio-chunk ordering and only sends immutable PCM.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.connectionID == id, !self.isDisconnecting else { return }
                self.send(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
                let now = Date()
                if now.timeIntervalSince(self.lastLevelEmit) >= 0.05 {
                    self.lastLevelEmit = now
                    self.emit(.microphoneLevel(VoiceInputMeter.level(pcm16: data)))
                }
            }
        }
        engine.prepare()
        do { try engine.start() }
        catch {
            input.removeTap(onBus: 0)
            throw RealtimeVoiceError.audioSessionFailed(error.localizedDescription)
        }
        audioEngine = engine
        observeAudioLifecycle(engine: engine, connectionID: id)
        emit(.microphoneStarted)
    }

    private func stopAudioCapture() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioEngine = nil
        }
        emit(.microphoneStopped)
    }

    private func observeAudioLifecycle(engine: AVAudioEngine, connectionID id: UUID) {
        let center = NotificationCenter.default
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification, AVAudioSession.mediaServicesWereLostNotification,
                     Notification.Name.AVAudioEngineConfigurationChange] {
            let object: AnyObject = name == Notification.Name.AVAudioEngineConfigurationChange ? engine : AVAudioSession.sharedInstance()
            audioObservers.append(center.addObserver(forName: name, object: object, queue: nil) { [weak self] notification in
                guard let event = VoiceAudioLifecycleEvent(notification: notification) else { return }
                Task { @MainActor [weak self] in
                    self?.handleAudioLifecycle(event, connectionID: id)
                }
            })
        }
    }

    func handleAudioLifecycle(_ event: VoiceAudioLifecycleEvent, connectionID id: UUID) {
        guard id == connectionID, !isDisconnecting else { return }
        // Never tear down an engine synchronously from its internal notification queue.
        failConnection(with: .error(loc(event == .interrupted ? "VoiceAudioInterrupted" : "VoiceAudioChanged")))
    }

    private func send(_ event: [String: Any]) {
        guard !isDisconnecting, let task = webSocketTask,
              let message = makeMessage(event) else { return }
        let id = connectionID
        task.send(message) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                guard let self, self.connectionID == id, !self.isDisconnecting else { return }
                self.failConnection(with: .error(error.localizedDescription))
            }
        }
    }

    private func sendAsync(_ event: [String: Any]) async throws {
        guard let task = webSocketTask, let message = makeMessage(event) else { throw RealtimeVoiceError.disconnected }
        try await task.send(message)
    }

    private func makeMessage(_ event: [String: Any]) -> URLSessionWebSocketTask.Message? {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return .string(text)
    }

    private func receiveLoop() {
        guard let task = webSocketTask else { return }
        let id = connectionID
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.connectionID == id, !self.isDisconnecting else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text): self.receiveServerEvent(Data(text.utf8), connectionID: id)
                    case .data(let data): self.receiveServerEvent(data, connectionID: id)
                    @unknown default: break
                    }
                    if !self.isDisconnecting { self.receiveLoop() }
                case .failure(let error): self.failConnection(with: .error(error.localizedDescription))
                }
            }
        }
    }

    func receiveServerEvent(_ data: Data, connectionID id: UUID) {
        guard id == connectionID, !isDisconnecting else { return }
        do {
            for event in try parser.parse(data) {
                guard id == connectionID, !isDisconnecting else { break }
                switch event {
                case .sessionReady, .functionArgumentsDelta: break
                case .listeningStarted: emit(.listeningStarted)
                case .listeningStopped: emit(.listeningStopped)
                case .responseStarted(let id, let app): emit(.responseStarted(id: id, isAppGenerated: app))
                case .responseFinished(let id): emit(.responseFinished(id: id))
                case .assistantTextDelta(let text): emit(.assistantTextDelta(text))
                case .assistantTextDone(let text): emit(.assistantText(text))
                case .workspaceSync(let payload, let callID):
                    emit(.workspaceSync(payload))
                    if let callID {
                        send(["type": "conversation.item.create", "item": ["type": "function_call_output",
                            "call_id": callID, "output": #"{"status":"ok"}"#]])
                    }
                case .error(let text): failConnection(with: .error(text))
                }
            }
        } catch { failConnection(with: .error(loc("VoiceInvalidResult"))) }
    }

    private func failConnection(with event: RealtimeVoiceServiceEvent) {
        guard !isDisconnecting else { return }
        disconnect()
        emit(event)
    }

    private func emit(_ event: RealtimeVoiceServiceEvent) {
        delegate?.realtimeVoiceService(self, didReceive: event)
    }
}

enum VoiceAudioLifecycleEvent: Equatable, Sendable {
    case interrupted, routeChanged, configurationChanged, mediaServicesReset

    init?(notification: Notification) {
        switch notification.name {
        case AVAudioSession.interruptionNotification:
            guard (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
                    == AVAudioSession.InterruptionType.began.rawValue else { return nil }
            self = .interrupted
        case AVAudioSession.routeChangeNotification:
            guard let raw = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  [.newDeviceAvailable, .oldDeviceUnavailable, .noSuitableRouteForCategory, .routeConfigurationChange].contains(reason) else { return nil }
            self = .routeChanged
        case Notification.Name.AVAudioEngineConfigurationChange: self = .configurationChanged
        case AVAudioSession.mediaServicesWereResetNotification, AVAudioSession.mediaServicesWereLostNotification: self = .mediaServicesReset
        default: return nil
        }
    }
}

extension RealtimeVoiceService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor [weak self] in
            guard let self, webSocketTask === self.webSocketTask, !self.isDisconnecting else { return }
            let continuation = self.webSocketOpenContinuation
            self.webSocketOpenContinuation = nil
            continuation?.resume()
            self.receiveLoop()
            self.emit(.connected)
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                               didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor [weak self] in
            guard let self, webSocketTask === self.webSocketTask else { return }
            self.failConnection(with: .disconnected)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            guard let self, task === self.webSocketTask else { return }
            if let continuation = self.webSocketOpenContinuation {
                self.webSocketOpenContinuation = nil
                continuation.resume(throwing: error)
            } else { self.failConnection(with: .error(error.localizedDescription)) }
        }
    }
}

/// One processor per tap; its converter is used only by that tap's serial callback.
private final class VoiceAudioProcessor: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!

    init(inputFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: target) else { throw RealtimeVoiceError.noMicrophoneInput }
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        let input = AudioConversionInput(buffer: buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            guard !input.didProvideBuffer else { status.pointee = .noDataNow; return nil }
            input.didProvideBuffer = true
            status.pointee = .haveData
            return input.buffer
        }
        guard status != .error else { return nil }
        let audio = output.audioBufferList.pointee.mBuffers
        guard let bytes = audio.mData, audio.mDataByteSize > 0 else { return nil }
        return Data(bytes: bytes, count: Int(audio.mDataByteSize))
    }
}

private final class AudioConversionInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var didProvideBuffer = false
    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}

enum VoiceInputMeter {
    /// Display-only gain: do not amplify or otherwise change the audio sent to the model.
    static func level(pcm16 data: Data) -> Double {
        guard !data.isEmpty, data.count.isMultiple(of: MemoryLayout<Int16>.size) else { return 0 }
        let sampleCount = data.count / MemoryLayout<Int16>.size
        let sum = data.withUnsafeBytes { bytes -> Double in
            var sum = 0.0
            for index in 0..<sampleCount {
                let pcm = Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                let sample = Double(pcm) / 32_768
                sum += sample * sample
            }
            return sum
        }
        let rms = sqrt(sum / Double(sampleCount))
        guard rms > 0 else { return 0 }
        // Quiet rooms fall below the floor; speech gets a useful visual range
        // without requiring near-clipping input to fully extend the bars.
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 55) / 40))
    }
}

enum RealtimeVoiceError: LocalizedError {
    case missingAPIKey
    case microphoneDenied
    case audioSessionFailed(String)
    case noMicrophoneInput
    case disconnected
    case webSocketFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add and verify your OpenAI API key in Settings first."
        case .microphoneDenied:
            return "Microphone access denied. Enable it in Settings → Mäuse."
        case .audioSessionFailed(let message):
            return "Could not activate the microphone: \(message)"
        case .noMicrophoneInput:
            return "No microphone input device is available."
        case .disconnected:
            return "The Realtime session disconnected."
        case .webSocketFailed(let message):
            return message
        }
    }
}
