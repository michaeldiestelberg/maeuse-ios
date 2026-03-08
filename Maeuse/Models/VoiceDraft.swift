import Foundation

/// Draft produced by the voice pipeline (transcription → cleanup → extraction)
struct VoiceDraft {
    var amount: Double?
    var description: String
    var dateISO: String
    var partnerShareMode: SplitMode?
    var partnerShareValue: Double?
    var isComplete: Bool
    var source: String

    static func empty(todayISO: String) -> VoiceDraft {
        VoiceDraft(
            amount: nil,
            description: "",
            dateISO: todayISO,
            partnerShareMode: nil,
            partnerShareValue: nil,
            isComplete: false,
            source: "empty"
        )
    }
}

/// Voice recording/processing phases
enum VoicePhase: String {
    case idle
    case recording
    case processing
    case review
    case error
}

/// Voice settings persisted in UserDefaults
struct VoiceSettings: Codable {
    var apiKey: String
    var verifiedAt: Date?
    var enabled: Bool

    static let storageKey = "maeuse.voice-settings"

    static var `default`: VoiceSettings {
        VoiceSettings(apiKey: "", verifiedAt: nil, enabled: false)
    }

    var isVerified: Bool {
        verifiedAt != nil && !apiKey.isEmpty
    }

    var isReady: Bool {
        enabled && isVerified
    }
}
