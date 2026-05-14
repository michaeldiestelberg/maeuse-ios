import Foundation
import Security

struct RealtimeClientSecret: Decodable {
    let value: String
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case value
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(String.self, forKey: .value)

        if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: timestamp)
        } else {
            expiresAt = nil
        }
    }
}

final class OpenAIAPIKeyStore: @unchecked Sendable {
    static let shared = OpenAIAPIKeyStore()

    private let service = "com.michaeldiestelberg.maeuse.openai"
    private let account = "openai-api-key"

    private init() {}

    func readAPIKey() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw OpenAIAPIKeyStoreError.keychainFailure(status)
        }

        guard let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8),
              !apiKey.isEmpty else {
            throw OpenAIAPIKeyStoreError.invalidStoredKey
        }

        return apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAIAPIKeyStoreError.emptyKey
        }

        try deleteAPIKey(ignoringMissing: true)

        guard let data = trimmed.data(using: .utf8) else {
            throw OpenAIAPIKeyStoreError.invalidStoredKey
        }

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OpenAIAPIKeyStoreError.keychainFailure(status)
        }
    }

    func deleteAPIKey(ignoringMissing: Bool = false) throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status == errSecItemNotFound && ignoringMissing {
            return
        }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAIAPIKeyStoreError.keychainFailure(status)
        }
    }

    func hasAPIKey() -> Bool {
        (try? readAPIKey()) != nil
    }

    static func suffix(for apiKey: String) -> String {
        String(apiKey.suffix(4))
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum OpenAIAPIKeyStoreError: LocalizedError {
    case emptyKey
    case invalidStoredKey
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "Enter an OpenAI API key first."
        case .invalidStoredKey:
            return "The saved OpenAI API key could not be read."
        case .keychainFailure(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

actor OpenAIRealtimeClientSecretService {
    func createClientSecret(apiKey: String) async throws -> RealtimeClientSecret {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIAPIKeyStoreError.emptyKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/client_secrets")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try RealtimeSessionConfiguration.requestBodyData()

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIRealtimeClientSecretError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            let message = OpenAIAPIErrorMessage.extract(from: data) ?? body
            throw OpenAIRealtimeClientSecretError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(RealtimeClientSecret.self, from: data)
        } catch {
            throw OpenAIRealtimeClientSecretError.decodeFailed
        }
    }
}

enum OpenAIRealtimeClientSecretError: LocalizedError {
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI did not return a valid HTTP response."
        case .requestFailed(let statusCode, let message):
            return "OpenAI client-secret request failed with status \(statusCode): \(message)"
        case .decodeFailed:
            return "OpenAI did not return a Realtime client secret."
        }
    }
}

private struct OpenAIAPIErrorMessage {
    static func extract(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        return object["message"] as? String
    }
}

enum RealtimeSessionConfiguration {
    static let model = "gpt-realtime-2"

    static func requestBodyData(now: Date = Date()) throws -> Data {
        try JSONSerialization.data(withJSONObject: requestBody(now: now))
    }

    static func requestBody(now: Date = Date()) -> [String: Any] {
        [
            "expires_after": [
                "anchor": "created_at",
                "seconds": 600
            ],
            "session": clientSecretSession(now: now)
        ]
    }

    static func clientSecretSession(now: Date = Date()) -> [String: Any] {
        [
            "type": "realtime",
            "model": model,
            "output_modalities": ["text"],
            "reasoning": [
                "effort": "low"
            ],
            "instructions": instructions(currentDateISO: isoDateFormatter.string(from: now)),
            "tools": [syncExpenseWorkspaceTool],
            "tool_choice": "auto",
            "audio": [
                "input": [
                    "format": [
                        "type": "audio/pcm",
                        "rate": 24000
                    ],
                    "transcription": [
                        "model": "gpt-realtime-whisper"
                    ],
                    "turn_detection": [
                        "type": "semantic_vad"
                    ]
                ]
            ]
        ]
    }

    static func webSocketSession(now: Date = Date()) -> [String: Any] {
        [
            "type": "realtime",
            "instructions": instructions(currentDateISO: isoDateFormatter.string(from: now)),
            "tools": [syncExpenseWorkspaceTool],
            "tool_choice": "auto",
            "output_modalities": ["text"],
            "audio": [
                "input": [
                    "format": [
                        "type": "audio/pcm",
                        "rate": 24000
                    ],
                    "transcription": [
                        "model": "gpt-realtime-whisper"
                    ],
                    "turn_detection": [
                        "type": "semantic_vad"
                    ]
                ]
            ],
            "reasoning": [
                "effort": "low"
            ]
        ]
    }

    private static func instructions(currentDateISO: String) -> String {
        """
        # Role and Objective
        You are Mäuse, a realtime expense-capture assistant for a couples expense tracker.
        Your job is to listen to the user's voice and keep a temporary workspace of expenses synchronized with what the user means.

        # Session Context
        - Current date: \(currentDateISO)
        - Each session starts with an empty workspace.
        - Capture one or more expenses from the conversation.
        - The user may correct, rename, split, date, or remove expenses by voice.
        - Do not save expenses yourself. The app saves the active workspace only when the user ends the session.
        - Use the sync_expense_workspace tool whenever the understood workspace changes or whenever a concise confirmation helps the user trust what you understood.
        - The visible "You" chat is built from raw input transcription. Do not use user_understanding to create a conversational rewrite.

        # Expense Fields
        - title: concise merchant, item, or purpose. Use null if not provided.
        - amount: total expense amount in euros. Use null if not provided.
        - date_iso: YYYY-MM-DD if explicit or confidently relative to the current date. If not provided, use the current date.
        - split_mode: percent or fixed. If not provided, use percent.
        - split_value: percentage or fixed euro share for the partner. If split details are not provided, use 50 with split_mode percent.
        - confidence: 0 to 1 estimate for the expense draft.
        - missing_fields: include title or amount when that field is missing or uncertain. Do not mark date or split missing just because the user did not say them.

        # Defaults
        Fill workspace defaults immediately so the user sees the result they would save:
        - Missing date defaults to \(currentDateISO).
        - Missing split defaults to split_mode percent and split_value 50.
        - Only leave title or amount null when missing.

        # Conversation Log Text
        - user_understanding is for app state only. Keep it concise and close to the latest relevant user meaning.
        - assistant_confirmation should be short and concrete, naming what changed.
        - If the audio is unclear, ask one short clarification in assistant_confirmation and keep the previous workspace unchanged.

        # Removal and Corrections
        - If the user removes an expense, omit it from the expenses array and include its id in removed_expense_ids.
        - Preserve stable ids for expenses across corrections.
        - Use changed_expense_ids for expenses whose fields changed in this turn.
        """
    }

    private static var syncExpenseWorkspaceTool: [String: Any] {
        [
            "type": "function",
            "name": "sync_expense_workspace",
            "description": "Synchronize the app's temporary expense workspace with the model's current understanding.",
            "parameters": [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "user_understanding": [
                        "type": "string",
                        "description": "A concise internal restatement of the user's latest relevant meaning. The app displays raw input transcription instead."
                    ],
                    "assistant_confirmation": [
                        "type": "string",
                        "description": "A short user-facing confirmation or clarification."
                    ],
                    "expenses": [
                        "type": "array",
                        "description": "The full active expense workspace after this turn.",
                        "items": [
                            "type": "object",
                            "additionalProperties": false,
                            "properties": [
                                "id": [
                                    "type": "string",
                                    "description": "Stable id for this draft across the session."
                                ],
                                "title": [
                                    "type": ["string", "null"],
                                    "description": "Merchant, item, or purpose. Null when missing."
                                ],
                                "amount": [
                                    "type": ["number", "null"],
                                    "description": "Total expense amount in euros. Null when missing."
                                ],
                                "date_iso": [
                                    "type": ["string", "null"],
                                    "description": "YYYY-MM-DD date. Use today's date when the user does not specify a date."
                                ],
                                "split_mode": [
                                    "type": ["string", "null"],
                                    "enum": ["percent", "fixed", NSNull()],
                                    "description": "Partner split mode. Use percent when the user does not specify split details."
                                ],
                                "split_value": [
                                    "type": ["number", "null"],
                                    "description": "Percent value or fixed euro amount, matching split_mode. Use 50 when split details are absent."
                                ],
                                "confidence": [
                                    "type": "number",
                                    "description": "Confidence from 0 to 1."
                                ],
                                "missing_fields": [
                                    "type": "array",
                                    "items": [
                                        "type": "string",
                                        "enum": ["title", "amount", "split", "date"]
                                    ],
                                    "description": "Fields that are missing or uncertain. Do not include date or split when applying the default date and 50 percent split."
                                ]
                            ],
                            "required": [
                                "id",
                                "title",
                                "amount",
                                "date_iso",
                                "split_mode",
                                "split_value",
                                "confidence",
                                "missing_fields"
                            ]
                        ]
                    ],
                    "changed_expense_ids": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Expense ids changed in this turn."
                    ],
                    "removed_expense_ids": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Expense ids removed in this turn."
                    ]
                ],
                "required": [
                    "user_understanding",
                    "assistant_confirmation",
                    "expenses",
                    "changed_expense_ids",
                    "removed_expense_ids"
                ]
            ]
        ]
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
