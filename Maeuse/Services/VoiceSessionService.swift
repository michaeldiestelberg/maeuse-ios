import Foundation

/// The chosen provider owns the entire audio-to-draft pipeline. No fallback provider.
@MainActor
protocol VoiceSessionService: AnyObject {
    var onEvent: ((RealtimeVoiceServiceEvent) -> Void)? { get set }
    func connect(workspaceContext: String?) async throws
    func disconnect()
    func sendWorkspaceNote(_ text: String)
    func finishTurn()
}

extension VoiceSessionService {
    func finishTurn() {}
}

enum VoiceProvider: String, Codable, CaseIterable, Identifiable {
    case appleLocal
    case openAI

    var id: String { rawValue }
    var title: String { loc(self == .appleLocal ? "VoiceAppleTitle" : "VoiceCloudTitle") }
}
