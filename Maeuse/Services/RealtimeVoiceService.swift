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
    case responseStarted
    case responseFinished
    case workspaceSync(VoiceWorkspaceSyncPayload)
    case userTranscriptDelta(itemID: String, text: String)
    case userTranscriptDone(itemID: String, text: String)
    case assistantText(String)
    case assistantTextDelta(String)
    case error(String)
}

// URLSession delegate callbacks and audio taps cross thread boundaries; the service
// owns that mutable state and hops UI-facing events back to the main actor.
final class RealtimeVoiceService: NSObject, @unchecked Sendable {
    @MainActor private weak var delegate: RealtimeVoiceServiceDelegate?

    private let logger = Logger(subsystem: "com.michaeldiestelberg.maeuse", category: "RealtimeVoice")
    private let apiKeyStore = OpenAIAPIKeyStore.shared
    private let eventQueue = DispatchQueue(label: "maeuse.realtime.events")
    private let audioSendQueue = DispatchQueue(label: "maeuse.realtime.audio-send")
    private let targetAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!

    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketOpenContinuation: CheckedContinuation<Void, Error>?
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var parser = RealtimeServerEventParser()
    private var isDisconnecting = false
    private var lastLevelEmit = Date.distantPast
    private var didReportLocalAudio = false
    private var didReportAudioUpload = false

    @MainActor
    func setDelegate(_ delegate: RealtimeVoiceServiceDelegate?) {
        self.delegate = delegate
    }

    func connect() async throws {
        logger.info("Starting Realtime voice connection.")
        disconnect()
        isDisconnecting = false

        guard let apiKey = try apiKeyStore.readAPIKey() else {
            throw RealtimeVoiceError.missingAPIKey
        }

        try await prepareAudioSession()
        try await connectWebSocket(apiKey: apiKey)
        try await sendSessionUpdate()
        try startAudioCapture()
    }

    func disconnect() {
        logger.info("Disconnecting Realtime voice session.")
        isDisconnecting = true

        stopAudioCapture()
        deactivateAudioSession()

        webSocketOpenContinuation?.resume(throwing: RealtimeVoiceError.disconnected)
        webSocketOpenContinuation = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        urlSession?.invalidateAndCancel()
        urlSession = nil

        parser = RealtimeServerEventParser()
        didReportLocalAudio = false
        didReportAudioUpload = false
    }

    func sendWorkspaceNote(_ text: String) {
        let event: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": text
                    ]
                ]
            ]
        ]
        send(event)
        sendTextResponseCreate()
    }

    private func connectWebSocket(apiKey: String) async throws {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [
            URLQueryItem(name: "model", value: RealtimeSessionConfiguration.model)
        ]

        guard let url = components.url else {
            throw RealtimeVoiceError.webSocketFailed("Could not create Realtime WebSocket URL.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        urlSession = session
        webSocketTask = task

        try await withCheckedThrowingContinuation { continuation in
            webSocketOpenContinuation = continuation
            task.resume()
        }
    }

    private func sendSessionUpdate() async throws {
        try await sendAsync([
            "type": "session.update",
            "session": RealtimeSessionConfiguration.webSocketSession()
        ])
    }

    private func sendTextResponseCreate() {
        send([
            "type": "response.create",
            "response": [
                "output_modalities": ["text"]
            ]
        ])
    }

    private func prepareAudioSession() async throws {
        let permitted = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }

        guard permitted else {
            throw RealtimeVoiceError.microphoneDenied
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
            logger.info("AVAudioSession active for Realtime voice capture.")
            emit(.microphoneReady)
        } catch {
            logger.error("Could not activate AVAudioSession: \(error.localizedDescription, privacy: .public)")
            throw RealtimeVoiceError.audioSessionFailed(error.localizedDescription)
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.warning("Could not deactivate AVAudioSession: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startAudioCapture() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.channelCount > 0 else {
            throw RealtimeVoiceError.noMicrophoneInput
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetAudioFormat) else {
            throw RealtimeVoiceError.audioSessionFailed("Could not create audio converter.")
        }

        audioConverter = converter
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RealtimeVoiceError.audioSessionFailed(error.localizedDescription)
        }

        audioEngine = engine
        logger.info("AVAudioEngine started for Realtime voice capture.")
        emit(.microphoneStarted)
    }

    private func stopAudioCapture() {
        guard let audioEngine else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        self.audioEngine = nil
        audioConverter = nil

        logger.info("AVAudioEngine stopped for Realtime voice capture.")
        emit(.microphoneStopped)
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        emitAudioLevel(from: buffer)

        guard let pcmData = convertToPCM16(buffer), !pcmData.isEmpty else {
            return
        }

        audioSendQueue.async { [weak self] in
            self?.sendAudioChunk(pcmData)
        }
    }

    private func emitAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }

        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channel[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameCount))
        let normalized = min(1, Double(rms) * 8)
        let now = Date()

        guard now.timeIntervalSince(lastLevelEmit) >= 0.1 else { return }
        lastLevelEmit = now

        if normalized > 0.04, !didReportLocalAudio {
            didReportLocalAudio = true
            logger.info("Local microphone audio detected.")
        }

        emit(.microphoneLevel(normalized))
    }

    private func convertToPCM16(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter = audioConverter else { return nil }

        let ratio = targetAudioFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetAudioFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        let input = AudioConversionInput(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if input.didProvideBuffer {
                outStatus.pointee = .noDataNow
                return nil
            }

            input.didProvideBuffer = true
            outStatus.pointee = .haveData
            return input.buffer
        }

        guard status != .error else {
            if let conversionError {
                logger.warning("Audio conversion failed: \(conversionError.localizedDescription, privacy: .public)")
            }
            return nil
        }

        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else {
            return nil
        }

        return Data(bytes: bytes, count: Int(audioBuffer.mDataByteSize))
    }

    private func sendAudioChunk(_ pcmData: Data) {
        guard !isDisconnecting, webSocketTask != nil else { return }

        if !didReportAudioUpload {
            didReportAudioUpload = true
            logger.info("Sending microphone audio chunks to OpenAI Realtime.")
        }

        send([
            "type": "input_audio_buffer.append",
            "audio": pcmData.base64EncodedString()
        ])
    }

    private func sendFunctionOutput(callID: String) {
        let event: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callID,
                "output": #"{"status":"ok"}"#
            ]
        ]
        send(event)
    }

    private func send(_ event: [String: Any]) {
        guard let webSocketTask else {
            logger.warning("Dropped Realtime client event because WebSocket is not connected.")
            return
        }

        guard let message = makeMessage(from: event) else {
            logger.warning("Dropped Realtime client event because JSON encoding failed.")
            return
        }

        webSocketTask.send(message) { [weak self] error in
            if let error, self?.isDisconnecting == false {
                self?.logger.error("Realtime WebSocket send failed: \(error.localizedDescription, privacy: .public)")
                self?.emit(.error("Realtime send failed: \(error.localizedDescription)"))
            }
        }
    }

    private func sendAsync(_ event: [String: Any]) async throws {
        guard let webSocketTask else {
            throw RealtimeVoiceError.disconnected
        }

        guard let message = makeMessage(from: event) else {
            throw RealtimeVoiceError.webSocketFailed("Could not encode Realtime event.")
        }

        try await webSocketTask.send(message)
    }

    private func makeMessage(from event: [String: Any]) -> URLSessionWebSocketTask.Message? {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return .string(string)
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handleWebSocketMessage(message)
                self.receiveLoop()
            case .failure(let error):
                guard !self.isDisconnecting else { return }
                self.logger.error("Realtime WebSocket receive failed: \(error.localizedDescription, privacy: .public)")
                self.emit(.error("Realtime session failed: \(error.localizedDescription)"))
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let string):
            handleServerEvent(Data(string.utf8))
        case .data(let data):
            handleServerEvent(data)
        @unknown default:
            break
        }
    }

    private func handleServerEvent(_ data: Data) {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = object["type"] as? String {
            logger.debug("Received Realtime server event: \(type, privacy: .public)")
        }

        eventQueue.async { [weak self] in
            guard let self else { return }
            do {
                let events = try self.parser.parse(data)
                for event in events {
                    self.handleParsedEvent(event)
                }
            } catch {
                self.emit(.error("Could not parse Realtime event: \(error.localizedDescription)"))
            }
        }
    }

    private func handleParsedEvent(_ event: RealtimeParsedEvent) {
        switch event {
        case .sessionReady:
            break
        case .listeningStarted:
            logger.info("OpenAI Realtime reported speech started.")
            emit(.listeningStarted)
        case .listeningStopped:
            logger.info("OpenAI Realtime reported speech stopped.")
            emit(.listeningStopped)
        case .responseStarted:
            logger.info("OpenAI Realtime response started.")
            emit(.responseStarted)
        case .responseFinished:
            logger.info("OpenAI Realtime response finished.")
            emit(.responseFinished)
        case .functionArgumentsDelta:
            break
        case .userTranscriptDelta(let itemID, let text):
            emit(.userTranscriptDelta(itemID: itemID, text: text))
        case .userTranscriptDone(let itemID, let text):
            emit(.userTranscriptDone(itemID: itemID, text: text))
        case .assistantTextDelta(let text):
            emit(.assistantTextDelta(text))
        case .assistantTextDone(let text):
            emit(.assistantText(text))
        case .workspaceSync(let payload, let callID):
            emit(.workspaceSync(payload))
            if let callID {
                sendFunctionOutput(callID: callID)
            }
        case .error(let message):
            emit(.error(message))
        }
    }

    private func emit(_ event: RealtimeVoiceServiceEvent) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.realtimeVoiceService(self, didReceive: event)
        }
    }
}

extension RealtimeVoiceService: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        logger.info("Realtime WebSocket opened.")
        webSocketOpenContinuation?.resume(returning: ())
        webSocketOpenContinuation = nil
        receiveLoop()
        emit(.connected)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        logger.info("Realtime WebSocket closed: \(String(describing: closeCode), privacy: .public)")
        guard !isDisconnecting else { return }
        emit(.disconnected)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            webSocketOpenContinuation?.resume(throwing: error)
            webSocketOpenContinuation = nil

            guard !isDisconnecting else { return }
            logger.error("Realtime WebSocket task failed: \(error.localizedDescription, privacy: .public)")
            emit(.error("Realtime session failed: \(error.localizedDescription)"))
        }
    }
}

private final class AudioConversionInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var didProvideBuffer = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
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
