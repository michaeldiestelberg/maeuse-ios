import Foundation

enum RealtimeParsedEvent: Equatable {
    case sessionReady
    case listeningStarted
    case listeningStopped
    case responseStarted(id: String, isAppGenerated: Bool)
    case responseFinished(id: String)
    case functionArgumentsDelta
    case assistantTextDelta(String)
    case assistantTextDone(String)
    case workspaceSync(VoiceWorkspaceSyncPayload, callID: String?)
    case error(String)
}

struct RealtimeServerEventParser {
    private var emittedFunctionCallIDs: Set<String> = []
    private var completedResponseIDs: Set<String> = []
    private var appGeneratedResponseIDs: Set<String> = []

    mutating func parse(_ data: Data) throws -> [RealtimeParsedEvent] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return [] }
        switch type {
        case "session.created", "session.updated": return [.sessionReady]
        case "input_audio_buffer.speech_started": return [.listeningStarted]
        case "input_audio_buffer.speech_stopped": return [.listeningStopped]
        case "response.created":
            recordResponseSource(object)
            let id = responseID(in: object)
            return [.responseStarted(id: id, isAppGenerated: appGeneratedResponseIDs.contains(id))]
        case "response.done":
            recordResponseSource(object)
            let id = responseID(in: object)
            if id != "unidentified-response", !completedResponseIDs.insert(id).inserted { return [] }
            return parseResponseDone(object) + [.responseFinished(id: id)]
        case "response.function_call_arguments.delta": return [.functionArgumentsDelta]
        case "response.function_call_arguments.done":
            // This event also occurs for cancelled/incomplete responses. Only the
            // final response contains both authoritative arguments and status.
            return []
        case "response.output_text.delta":
            guard let text = object["delta"] as? String, !text.isEmpty else { return [] }
            return [.assistantTextDelta(text)]
        case "response.output_text.done":
            guard let text = object["text"] as? String, !text.isEmpty else { return [] }
            return [.assistantTextDone(text)]
        case "error": return [.error(parseErrorMessage(object))]
        default: return []
        }
    }

    private mutating func parseResponseDone(_ object: [String: Any]) -> [RealtimeParsedEvent] {
        guard let response = object["response"] as? [String: Any] else {
            return [.error(loc("VoiceInvalidResult"))]
        }
        let status = response["status"] as? String ?? "completed"
        if status == "cancelled" { return [] }
        if status != "completed" {
            return [.error(loc(status == "incomplete" ? "VoiceIncompleteResult" : "VoiceResponseFailed"))]
        }
        guard let output = response["output"] as? [[String: Any]] else {
            return [.error(loc("VoiceInvalidResult"))]
        }
        let id = response["id"] as? String
        var decoded: [(VoiceWorkspaceSyncPayload, String?)] = []
        var hasTool = false
        for item in output where item["type"] as? String == "function_call" {
            hasTool = true
            let callID = item["call_id"] as? String
            if let callID, emittedFunctionCallIDs.contains(callID) { continue }
            guard item["name"] as? String == "sync_expense_workspace",
                  let arguments = item["arguments"] as? String,
                  let data = arguments.data(using: .utf8),
                  var payload = try? JSONDecoder().decode(VoiceWorkspaceSyncPayload.self, from: data) else {
                return [.error(loc("VoiceInvalidResult"))]
            }
            payload.responseID = id ?? callID
            payload.isAppGenerated = id.map { appGeneratedResponseIDs.contains($0) } ?? false
            decoded.append((payload, callID))
        }
        // Never publish part of a response when another tool call in it is invalid.
        if !hasTool, !appGeneratedResponseIDs.contains(id ?? "") {
            return [.error(loc("VoiceInvalidResult"))]
        }
        return decoded.map { payload, callID in
            if let callID { emittedFunctionCallIDs.insert(callID) }
            return .workspaceSync(payload, callID: callID)
        }
    }

    private func responseID(in object: [String: Any]) -> String {
        (object["response"] as? [String: Any])?["id"] as? String ?? "unidentified-response"
    }

    private mutating func recordResponseSource(_ object: [String: Any]) {
        guard let response = object["response"] as? [String: Any],
              let id = response["id"] as? String,
              let metadata = response["metadata"] as? [String: String],
              metadata["maeuse_source"] == "workspace_note" else { return }
        appGeneratedResponseIDs.insert(id)
    }

    private func parseErrorMessage(_ object: [String: Any]) -> String {
        (object["error"] as? [String: Any])?["message"] as? String
            ?? object["message"] as? String ?? loc("VoiceResponseFailed")
    }
}
