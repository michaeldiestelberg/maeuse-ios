import Foundation
import FoundationModels
import Speech

struct AppleVoiceAvailability: Equatable {
    let canStart: Bool
    let messageKey: String

    static let checking = Self(canStart: false, messageKey: "AppleChecking")
    // Do not enable until Apple grants the managed entitlement and signing is updated.
    static let privateCloudComputeEnabledInBuild = false

    static func check(locale: Locale) async -> Self {
        #if targetEnvironment(simulator)
        // The iOS 27 runtime can advertise availability but rejects inference as unsupported.
        return Self(canStart: false, messageKey: "AppleSimulatorUnavailable")
        #else
        guard #available(iOS 26, *) else {
            return Self(canStart: false, messageKey: "AppleRequiresOS")
        }
        switch SystemLanguageModel.default.availability {
        case .available: break
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return Self(canStart: false, messageKey: "AppleEnableIntelligence")
            case .deviceNotEligible:
                return Self(canStart: false, messageKey: "AppleDeviceUnsupported")
            case .modelNotReady:
                return Self(canStart: false, messageKey: "AppleModelNotReady")
            @unknown default:
                return Self(canStart: false, messageKey: "AppleUnavailable")
            }
        @unknown default:
            return Self(canStart: false, messageKey: "AppleUnavailable")
        }
        guard SystemLanguageModel.default.supportsLocale(locale), SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return Self(canStart: false, messageKey: "AppleLanguageUnsupported")
        }
        let module = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        let status = await AssetInventory.status(forModules: [module])
        switch status {
        case .installed: return Self(canStart: true, messageKey: "AppleReady")
        case .supported, .downloading: return Self(canStart: true, messageKey: "AppleAssetsRequired")
        case .unsupported: return Self(canStart: false, messageKey: "AppleLanguageUnsupported")
        @unknown default: return Self(canStart: false, messageKey: "AppleUnavailable")
        }
        #endif
    }
}

enum AppleVoiceError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let key): return loc(key) }
    }
}
