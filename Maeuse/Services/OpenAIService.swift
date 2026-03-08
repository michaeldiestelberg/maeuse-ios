import Foundation

/// Handles all OpenAI API interactions: key verification, transcription, cleanup, extraction
actor OpenAIService {
    private let transcriptionModel = "gpt-4o-transcribe"
    private let cleanupModel = "gpt-5.4"
    private let extractModel = "gpt-5.4"

    // MARK: - Verify API Key

    func verifyAPIKey(_ key: String) async throws -> Bool {
        guard !key.isEmpty else { return false }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    // MARK: - Transcribe Audio

    func transcribe(audioURL: URL, apiKey: String) async throws -> String {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent

        var body = Data()
        // Model field
        body.appendMultipart(boundary: boundary, name: "model", value: transcriptionModel)
        // Prompt field
        let prompt = [
            "Expense dictation for a couples expense tracker.",
            "The speaker may mix English and German.",
            "Transcribe faithfully.",
            "Preserve self-corrections, restarts, merchant names, euro amounts, cents, dates, percentages, and partner references.",
            "Use normal punctuation.",
            "Do not clean up meaning or resolve corrections."
        ].joined(separator: " ")
        body.appendMultipart(boundary: boundary, name: "prompt", value: prompt)
        // Response format
        body.appendMultipart(boundary: boundary, name: "response_format", value: "text")
        // Audio file
        body.appendMultipartFile(boundary: boundary, name: "file", filename: filename, mimeType: "audio/mp4", data: audioData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.apiError(errorBody)
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Cleanup Transcript

    func cleanupTranscript(_ rawTranscript: String, apiKey: String) async throws -> String {
        let systemPrompt = [
            "You convert one raw expense-dictation transcript into one cleaned transcript for user review and downstream extraction.",
            "Output contract: return ONLY a JSON object with one key 'cleaned_transcript'.",
            "cleaned_transcript must be one concise natural utterance, or an empty string if the transcript is unusable.",
            "Rules: preserve the final intended meaning exactly.",
            "Remove filler words, hesitation noises, obvious false starts, and duplicated fragments that do not change meaning.",
            "If the speaker corrects themselves, keep only the final intended value.",
            "Preserve merchant names, euro amounts, cents, dates, split percentages, fixed split amounts, and partner references.",
            "Do not invent facts, summarize, explain, or add metadata."
        ].joined(separator: " ")

        let responseJSON = try await chatCompletion(
            systemPrompt: systemPrompt,
            userMessage: rawTranscript,
            apiKey: apiKey,
            model: cleanupModel,
            reasoningEffort: "low"
        )

        // Parse the cleaned transcript
        if let data = responseJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cleaned = json["cleaned_transcript"] as? String {
            return cleaned
        }

        return rawTranscript
    }

    // MARK: - Extract Expense Data

    func extractExpense(cleanedTranscript: String, todayISO: String, apiKey: String) async throws -> VoiceDraft {
        let systemPrompt = [
            "You extract one expense draft from one cleaned expense transcript.",
            "Output contract: return ONLY a JSON object matching this schema:",
            "{\"amount\": number|null, \"description\": string, \"date_iso\": string|null,",
            "\"partner_share_mode\": \"percent\"|\"fixed\"|null,",
            "\"partner_share_value\": number|null,",
            "\"is_complete\": boolean}",
            "Field rules: amount is the total expense in euros.",
            "description is a concise merchant-and-purpose description when inferable, otherwise empty string.",
            "date_iso must be YYYY-MM-DD when explicitly inferable relative to today (\(todayISO)); otherwise null.",
            "If the speaker gives a percentage split, set partner_share_mode to percent and partner_share_value to that percentage.",
            "If the speaker gives a fixed partner amount, set partner_share_mode to fixed and partner_share_value to that euro amount.",
            "If split details are absent or ambiguous, leave the split fields null.",
            "Do not invent values."
        ].joined(separator: " ")

        let responseJSON = try await chatCompletion(
            systemPrompt: systemPrompt,
            userMessage: cleanedTranscript,
            apiKey: apiKey,
            model: extractModel,
            reasoningEffort: "none"
        )

        return parseVoiceDraft(from: responseJSON, todayISO: todayISO)
    }

    // MARK: - Chat Completion

    private func chatCompletion(
        systemPrompt: String,
        userMessage: String,
        apiKey: String,
        model: String,
        reasoningEffort: String? = nil
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0
        ]

        if let effort = reasoningEffort {
            body["reasoning_effort"] = effort
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.apiError(errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.parseError
        }

        // Strip markdown code fences if present
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            let filtered = lines.dropFirst().dropLast().joined(separator: "\n")
            return filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    // MARK: - Parse Voice Draft

    private func parseVoiceDraft(from jsonString: String, todayISO: String) -> VoiceDraft {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .empty(todayISO: todayISO)
        }

        let amount = json["amount"] as? Double
        let description = json["description"] as? String ?? ""
        let dateIso = json["date_iso"] as? String
        let shareMode = json["partner_share_mode"] as? String
        let shareValue = json["partner_share_value"] as? Double
        let isComplete = json["is_complete"] as? Bool ?? (amount != nil && amount! > 0)

        var mode: SplitMode? = nil
        if shareMode == "percent" { mode = .percent }
        else if shareMode == "fixed" { mode = .fixed }

        return VoiceDraft(
            amount: amount,
            description: description,
            dateISO: dateIso ?? todayISO,
            partnerShareMode: mode,
            partnerShareValue: shareValue,
            isComplete: isComplete,
            source: "model"
        )
    }
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "OpenAI API error: \(msg)"
        case .parseError: return "Failed to parse OpenAI response"
        }
    }
}

// MARK: - Multipart Helpers

extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
