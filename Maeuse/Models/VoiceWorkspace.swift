import Foundation

/// Realtime voice workspace phases.
enum VoicePhase: String {
    case idle
    case connecting
    case listening
    case thinking
    case finalizing
    case error
}

enum VoiceConversationRole: String {
    case user
    case assistant
    case system
}

struct VoiceConversationEntry: Identifiable, Equatable {
    let id: String
    let role: VoiceConversationRole
    let text: String
    let createdAt: Date

    init(id: String = UUID().uuidString, role: VoiceConversationRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

enum VoiceExpenseMissingField: String, Codable, CaseIterable, Identifiable {
    case title
    case amount
    case split
    case date

    var id: String { rawValue }
}

struct VoiceExpenseDraft: Identifiable, Equatable {
    var id: String
    var title: String
    var amount: Double?
    var dateISO: String?
    var splitMode: SplitMode?
    var splitValue: Double?
    var confidence: Double
    var missingFields: [VoiceExpenseMissingField]
    var lastChangedAt: Date

    init(
        id: String,
        title: String,
        amount: Double?,
        dateISO: String?,
        splitMode: SplitMode?,
        splitValue: Double?,
        confidence: Double,
        missingFields: [VoiceExpenseMissingField],
        lastChangedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.dateISO = dateISO
        self.splitMode = splitMode
        self.splitValue = splitValue
        self.confidence = confidence
        self.missingFields = missingFields
        self.lastChangedAt = lastChangedAt
    }

    var normalizedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? loc("UntitledExpense") : trimmed
    }

    var normalizedAmount: Double {
        guard let amount, amount.isFinite else { return 0 }
        return max(0, amount).roundedMoney
    }

    var normalizedSplitMode: SplitMode {
        splitMode ?? .percent
    }

    var normalizedSplitValue: Double {
        let proposedValue = splitValue ?? 50
        guard proposedValue.isFinite else { return 50 }

        switch normalizedSplitMode {
        case .percent:
            return min(max(proposedValue, 0), 100)
        case .fixed:
            return min(max(proposedValue, 0), normalizedAmount)
        }
    }

    var isReadyForSaving: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let amount,
              amount.isFinite,
              amount > 0 else {
            return false
        }

        let proposedSplit = splitValue ?? 50
        guard proposedSplit.isFinite, proposedSplit >= 0 else { return false }

        switch normalizedSplitMode {
        case .percent:
            return proposedSplit <= 100
        case .fixed:
            return true
        }
    }

    func normalizedDate(defaultISO: String) -> Date {
        Expense.dateFromISO(dateISO ?? defaultISO) ?? Date()
    }

    var partnerShare: Double {
        switch normalizedSplitMode {
        case .percent:
            return (normalizedAmount * normalizedSplitValue / 100).roundedMoney
        case .fixed:
            return min(normalizedSplitValue, normalizedAmount).roundedMoney
        }
    }
}

struct VoiceWorkspaceSyncPayload: Decodable, Equatable {
    let userUnderstanding: String
    let assistantConfirmation: String
    let expenses: [VoiceExpenseDraftPayload]
    let changedExpenseIDs: [String]
    let removedExpenseIDs: [String]

    enum CodingKeys: String, CodingKey {
        case userUnderstanding = "user_understanding"
        case assistantConfirmation = "assistant_confirmation"
        case expenses
        case changedExpenseIDs = "changed_expense_ids"
        case removedExpenseIDs = "removed_expense_ids"
    }
}

struct VoiceExpenseDraftPayload: Decodable, Equatable {
    let id: String
    let title: String?
    let amount: Double?
    let dateISO: String?
    let splitMode: String?
    let splitValue: Double?
    let confidence: Double
    let missingFields: [VoiceExpenseMissingField]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case amount
        case dateISO = "date_iso"
        case splitMode = "split_mode"
        case splitValue = "split_value"
        case confidence
        case missingFields = "missing_fields"
    }

    var draft: VoiceExpenseDraft {
        VoiceExpenseDraft(
            id: id,
            title: title ?? "",
            amount: amount,
            dateISO: dateISO,
            splitMode: splitMode.flatMap(SplitMode.init(rawValue:)),
            splitValue: splitValue,
            confidence: min(max(confidence, 0), 1),
            missingFields: missingFields
        )
    }
}

/// Voice settings persisted in UserDefaults
struct VoiceSettings: Codable {
    var apiKeySuffix: String?
    var verifiedAt: Date?
    var enabled: Bool
    var hapticsEnabled: Bool
    var consentVersion: Int?
    var consentedAt: Date?

    static let storageKey = "maeuse.voice-settings"
    static let currentConsentVersion = 1

    static var `default`: VoiceSettings {
        VoiceSettings(
            apiKeySuffix: nil,
            verifiedAt: nil,
            enabled: false,
            hapticsEnabled: true,
            consentVersion: nil,
            consentedAt: nil
        )
    }

    init(
        apiKeySuffix: String?,
        verifiedAt: Date?,
        enabled: Bool,
        hapticsEnabled: Bool = true,
        consentVersion: Int?,
        consentedAt: Date?
    ) {
        self.apiKeySuffix = apiKeySuffix
        self.verifiedAt = verifiedAt
        self.enabled = enabled
        self.hapticsEnabled = hapticsEnabled
        self.consentVersion = consentVersion
        self.consentedAt = consentedAt
    }

    enum CodingKeys: String, CodingKey {
        case apiKeySuffix
        case verifiedAt
        case enabled
        case hapticsEnabled
        case consentVersion
        case consentedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKeySuffix = try container.decodeIfPresent(String.self, forKey: .apiKeySuffix)
        verifiedAt = try container.decodeIfPresent(Date.self, forKey: .verifiedAt)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        consentVersion = try container.decodeIfPresent(Int.self, forKey: .consentVersion)
        consentedAt = try container.decodeIfPresent(Date.self, forKey: .consentedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(apiKeySuffix, forKey: .apiKeySuffix)
        try container.encodeIfPresent(verifiedAt, forKey: .verifiedAt)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(hapticsEnabled, forKey: .hapticsEnabled)
        try container.encodeIfPresent(consentVersion, forKey: .consentVersion)
        try container.encodeIfPresent(consentedAt, forKey: .consentedAt)
    }

    var isVerified: Bool {
        verifiedAt != nil && apiKeySuffix != nil
    }

    var isReady: Bool {
        enabled && isVerified && hasCurrentConsent
    }

    var hasCurrentConsent: Bool {
        consentVersion == Self.currentConsentVersion && consentedAt != nil
    }

    var maskedAPIKey: String {
        guard let apiKeySuffix else { return "" }
        return "•••• \(apiKeySuffix)"
    }
}
