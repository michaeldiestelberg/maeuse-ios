import Foundation
import FoundationModels

/// Technical metadata only: no audio, transcript, titles, amounts or model output.
struct LocalVoiceDiagnostic: Equatable {
    let turnID: String
    let version: String
    let build: String
    let os: String
    let language: String
    let modelVariant: String
    let modelAvailability: String
    let timeZone: String
    let referenceDate: String
    var captureEnd = "not-finished"
    var stage = "speech"
    var elapsedMilliseconds = 0
    var steps: [String] = []
    var isTerminal = false
    var issue: LocalVoiceIssue?

    var exportText: String {
        (["Mäuse \(version) (\(build))", "OS: \(os)", "Model: \(modelVariant)",
          "Availability: \(modelAvailability)", "Language: \(language)",
          "Zone: \(timeZone); reference: \(referenceDate)", "Turn: \(turnID)",
          "Capture end: \(captureEnd)", "Stage: \(stage); elapsed: \(elapsedMilliseconds) ms",
          "Issue: \(issue?.category.rawValue ?? "none"); reason: \(issue?.reason ?? "none")",
          "Error: \(issue?.domain ?? "none") / \(issue?.code.map(String.init) ?? "none")"] + steps).joined(separator: "\n")
    }
}

struct LocalVoiceIssue: Equatable {
    enum Category: String {
        case timeout, assets, unavailable, language, schema, context, guardrail, refusal
        case busy, rateLimited, invalidPlan, speech, interrupted, unknown
        var message: String {
            switch self {
            case .timeout: return loc("LocalModelTimeout")
            case .assets, .unavailable: return loc("LocalModelNotReady")
            case .language: return loc("LocalLanguageUnsupported")
            case .guardrail, .refusal: return loc("LocalModelBlocked")
            case .busy, .rateLimited: return loc("LocalModelBusy")
            case .schema, .invalidPlan: return loc("LocalModelInvalidPlan")
            case .speech: return loc("LocalRecognitionFailed")
            case .interrupted: return loc("VoiceAudioInterrupted")
            case .context, .unknown: return loc("LocalGenerationFailed")
            }
        }
    }
    let category: Category
    let reason: String? // App-owned constant; never a provider description.
    let domain: String?
    let code: Int?

    init(_ category: Category, reason: String? = nil, domain: String? = nil, code: Int? = nil) {
        self.category = category; self.reason = reason; self.domain = domain; self.code = code
    }

    @available(iOS 26.0, macOS 26.0, *)
    static func classify(_ error: Error) -> Self {
        if let failure = error as? LocalVoiceFailure { return failure.issue }
        if let invalid = error as? VoiceWorkspaceDomain.InvalidChange {
            let reason: String
            switch invalid { case .invalidIdentity: reason = "domain-identity"; case .invalidValue: reason = "domain-value"; case .tooManyDrafts: reason = "draft-limit" }
            return .init(.invalidPlan, reason: reason)
        }
        let ns = error as NSError
        // Keep known framework domains; provider descriptions/metadata can contain inputs.
        let domain = ns.domain.hasPrefix("FoundationModels") || ns.domain.hasPrefix("com.apple.") ? ns.domain : "other"
        var category: Category = .unknown
        if #available(iOS 27.0, macOS 27.0, *) {
            if let modelError = error as? LanguageModelError {
                switch modelError {
                case .contextSizeExceeded: category = .context
                case .rateLimited: category = .rateLimited
                case .guardrailViolation: category = .guardrail
                case .refusal: category = .refusal
                case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide: category = .schema
                case .unsupportedLanguageOrLocale: category = .language
                case .timeout: category = .timeout
                @unknown default: break
                }
            } else if error is SystemLanguageModel.Error { category = .assets }
            else if error is LanguageModelSession.Error { category = .busy }
            else if error is GeneratedContent.ParsingError { category = .schema }
        } else {
            category = legacyCategory(error)
        }
        if error is DecodingError { category = .schema }
        return .init(category, domain: domain, code: ns.code)
    }

    @available(iOS, introduced: 26.0, deprecated: 27.0)
    @available(macOS, introduced: 26.0, deprecated: 27.0)
    private static func legacyCategory(_ error: Error) -> Category {
        guard let error = error as? LanguageModelSession.GenerationError else { return .unknown }
        switch error {
        case .exceededContextWindowSize: return .context
        case .assetsUnavailable: return .assets
        case .guardrailViolation: return .guardrail
        case .unsupportedGuide, .decodingFailure: return .schema
        case .unsupportedLanguageOrLocale: return .language
        case .rateLimited: return .rateLimited
        case .concurrentRequests: return .busy
        case .refusal: return .refusal
        @unknown default: return .unknown
        }
    }
}

struct LocalVoiceFailure: LocalizedError {
    let issue: LocalVoiceIssue
    var errorDescription: String? { issue.category.message }
}

@MainActor
final class LocalVoiceTrace {
    private let clock: () -> TimeInterval
    private let started: TimeInterval
    private var stepStarted: TimeInterval
    private(set) var snapshot: LocalVoiceDiagnostic
    var onUpdate: ((LocalVoiceDiagnostic) -> Void)?

    init(language: String, modelVariant: String, availability: String, referenceDate: String,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        started = clock(); stepStarted = started
        snapshot = .init(turnID: String(UUID().uuidString.prefix(8)),
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            os: ProcessInfo.processInfo.operatingSystemVersionString, language: language,
            modelVariant: modelVariant, modelAvailability: availability,
            timeZone: TimeZone.current.identifier, referenceDate: referenceDate)
    }

    func begin(_ stage: String) {
        snapshot.stage = stage; stepStarted = clock(); publish()
    }
    func endStep() {
        append("\(snapshot.stage): \(milliseconds(clock() - stepStarted)) ms")
        publish()
    }
    func captureEnded(_ reason: String) { snapshot.captureEnd = reason; publish() }
    func record(_ issue: LocalVoiceIssue) {
        snapshot.issue = issue
        append("\(snapshot.stage): \(issue.category.rawValue)/\(issue.reason ?? "none")")
        publish()
    }
    func completed() { snapshot.stage = "complete"; snapshot.isTerminal = true; publish() }
    func failed(_ issue: LocalVoiceIssue) { snapshot.isTerminal = true; record(issue) }
    private func append(_ text: String) {
        snapshot.steps.append(text)
        if snapshot.steps.count > 32 { snapshot.steps.removeFirst(snapshot.steps.count - 32) }
    }
    private func milliseconds(_ seconds: TimeInterval) -> Int { Int(max(0, seconds) * 1_000) }
    private func publish() {
        snapshot.elapsedMilliseconds = milliseconds(clock() - started)
        onUpdate?(snapshot)
    }
}

enum LocalVoiceTraceScope {
    @TaskLocal static var current: LocalVoiceTrace?
}
