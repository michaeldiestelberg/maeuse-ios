import Foundation

enum RealtimeParsedEvent: Equatable {
    case sessionReady
    case listeningStarted
    case listeningStopped
    case responseStarted
    case responseFinished
    case functionArgumentsDelta
    case userTranscriptDelta(itemID: String, text: String)
    case userTranscriptDone(itemID: String, text: String)
    case assistantTextDelta(String)
    case assistantTextDone(String)
    case workspaceSync(VoiceWorkspaceSyncPayload, callID: String?)
    case error(String)
}

struct RealtimeServerEventParser {
    private var functionArgumentBuffers: [String: String] = [:]
    private var emittedFunctionCallIDs: Set<String> = []

    mutating func parse(_ data: Data) throws -> [RealtimeParsedEvent] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return []
        }

        switch type {
        case "session.created", "session.updated":
            return [.sessionReady]

        case "input_audio_buffer.speech_started":
            return [.listeningStarted]

        case "input_audio_buffer.speech_stopped":
            return [.listeningStopped]

        case "response.created":
            return [.responseStarted]

        case "response.done":
            var events = parseResponseDone(object)
            events.append(.responseFinished)
            return events

        case "response.function_call_arguments.delta":
            let key = functionCallBufferKey(from: object)
            let delta = object["delta"] as? String ?? ""
            functionArgumentBuffers[key, default: ""] += delta
            return [.functionArgumentsDelta]

        case "response.function_call_arguments.done":
            return parseFunctionArgumentsDone(object)

        case "conversation.item.input_audio_transcription.delta":
            let itemID = transcriptItemID(from: object)
            let delta = object["delta"] as? String ?? ""
            guard !delta.isEmpty else { return [] }
            return [.userTranscriptDelta(itemID: itemID, text: delta)]

        case "conversation.item.input_audio_transcription.completed":
            let itemID = transcriptItemID(from: object)
            let transcript = object["transcript"] as? String ?? ""
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            return [.userTranscriptDone(itemID: itemID, text: transcript)]

        case "conversation.item.input_audio_transcription.failed":
            return [.error(parseTranscriptionErrorMessage(object))]

        case "response.output_text.delta":
            guard let delta = object["delta"] as? String, !delta.isEmpty else { return [] }
            return [.assistantTextDelta(delta)]

        case "response.output_text.done":
            guard let text = object["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            return [.assistantTextDone(text)]

        case "error":
            return [.error(parseErrorMessage(object))]

        default:
            return []
        }
    }

    private mutating func parseResponseDone(_ object: [String: Any]) -> [RealtimeParsedEvent] {
        guard let response = object["response"] as? [String: Any],
              let output = response["output"] as? [[String: Any]] else {
            return []
        }

        return output.compactMap { item in
            guard item["type"] as? String == "function_call",
                  item["name"] as? String == "sync_expense_workspace",
                  let arguments = item["arguments"] as? String else {
                return nil
            }

            let callID = item["call_id"] as? String
            if let callID, emittedFunctionCallIDs.contains(callID) {
                return nil
            }
            if let callID {
                emittedFunctionCallIDs.insert(callID)
            }
            return decodeWorkspaceSync(arguments, callID: callID)
        }
    }

    private mutating func parseFunctionArgumentsDone(_ object: [String: Any]) -> [RealtimeParsedEvent] {
        let key = functionCallBufferKey(from: object)
        let arguments = object["arguments"] as? String ?? functionArgumentBuffers[key] ?? ""
        functionArgumentBuffers[key] = nil

        guard (object["name"] as? String == nil) || object["name"] as? String == "sync_expense_workspace" else {
            return []
        }

        let callID = object["call_id"] as? String
        if let callID {
            emittedFunctionCallIDs.insert(callID)
        }
        if let event = decodeWorkspaceSync(arguments, callID: callID) {
            return [event]
        }
        return []
    }

    private func decodeWorkspaceSync(_ arguments: String, callID: String?) -> RealtimeParsedEvent? {
        guard let data = arguments.data(using: .utf8),
              let payload = try? JSONDecoder().decode(VoiceWorkspaceSyncPayload.self, from: data) else {
            return nil
        }
        return .workspaceSync(payload, callID: callID)
    }

    private func functionCallBufferKey(from object: [String: Any]) -> String {
        if let callID = object["call_id"] as? String { return callID }
        if let itemID = object["item_id"] as? String { return itemID }
        if let outputIndex = object["output_index"] { return "output-\(outputIndex)" }
        return "default"
    }

    private func transcriptItemID(from object: [String: Any]) -> String {
        object["item_id"] as? String ?? "default"
    }

    private func parseErrorMessage(_ object: [String: Any]) -> String {
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        if let message = object["message"] as? String {
            return message
        }

        return "Realtime session failed."
    }

    private func parseTranscriptionErrorMessage(_ object: [String: Any]) -> String {
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return "Input transcription failed: \(message)"
        }

        return "Input transcription failed."
    }
}
