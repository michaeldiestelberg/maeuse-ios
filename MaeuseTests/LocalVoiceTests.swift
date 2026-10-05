import XCTest
import AVFoundation
import UIKit
@testable import Maeuse

@MainActor
final class LocalVoiceTests: XCTestCase {
    func testListeningFeedbackFollowsActualCaptureNotResumeIntentOrAudio() {
        let vm = VoiceModeViewModel()
        vm.open(provider: .appleLocal)
        XCTAssertTrue(vm.localShouldListen)
        XCTAssertFalse(vm.localCaptureIsActive, "Opening intent must not light the halo")
        for _ in 0..<3 {
            vm.handleVoiceEvent(.microphoneStarted)
            XCTAssertTrue(vm.localCaptureIsActive)
            for level in [0.0, 0.05, 0.8, 0.0] {
                vm.handleVoiceEvent(.microphoneLevel(level))
                XCTAssertTrue(vm.localCaptureIsActive, "Audio must not drive the halo or glyph")
            }
            vm.handleVoiceEvent(.microphoneStopped)
            vm.handleVoiceEvent(.responseStarted(id: "turn", isAppGenerated: false))
            XCTAssertFalse(vm.localCaptureIsActive)
            XCTAssertTrue(vm.localShouldListen)
            vm.toggleLocalRecording()
            XCTAssertFalse(vm.localShouldListen)
            XCTAssertFalse(vm.localCaptureIsActive)
            vm.toggleLocalRecording()
            XCTAssertTrue(vm.localShouldListen)
            XCTAssertFalse(vm.localCaptureIsActive, "Resume intent during inference is not capture")
            vm.handleVoiceEvent(.responseFinished(id: "turn"))
        }
        vm.suspendLocalRecording()
        XCTAssertFalse(vm.localCaptureIsActive)
        vm.handleVoiceEvent(.error("Interrupted"))
        XCTAssertFalse(vm.localCaptureIsActive)
        vm.cancelSession()
        vm.open(provider: .openAI)
        vm.handleVoiceEvent(.microphoneStarted)
        XCTAssertFalse(vm.localCaptureIsActive)
        vm.cancelSession()
    }

    func testIntentionalRecognitionFinishDoesNotConvertSilenceToFailure() {
        XCTAssertEqual(LocalRecognitionCompletion.action(final: false, failed: true, finishing: true), .complete)
        XCTAssertEqual(LocalRecognitionCompletion.action(final: false, failed: true, finishing: false), .fail)
        XCTAssertEqual(LocalRecognitionCompletion.action(final: true, failed: false, finishing: false), .complete)
        XCTAssertEqual(LocalRecognitionCompletion.action(final: false, failed: false, finishing: true), .wait)
    }

    func testCountdownSettlesAndFadesWithoutBackwardResetAcrossRepeatedPhrases() {
        var endpoint = LocalSpeechEndpoint()
        var indicator = LocalEndpointIndicator()
        for start in [10.0, 20.0, 30.0] {
            endpoint.updateTranscript("Coffee \(start)", at: start)
            endpoint.observeLevel(0.2, at: start)
            XCTAssertEqual(endpoint.indicatorProgress(at: start + 0.6), 0)
            indicator.update(endpoint.indicatorProgress(at: start + 0.8))
            XCTAssertTrue(indicator.isVisible)
            XCTAssertEqual(indicator.progress, endpoint.progress(at: start + 0.8))
            let heldArc = indicator.progress
            endpoint.observeLevel(0.2, at: start + 0.9)
            indicator.update(endpoint.indicatorProgress(at: start + 0.9))
            XCTAssertFalse(indicator.isVisible)
            XCTAssertEqual(indicator.progress, heldArc, "Hide the arc without rewinding it")
            XCTAssertFalse(endpoint.shouldFinish(at: start + 3.0))
            XCTAssertTrue(endpoint.shouldFinish(at: start + 3.2), "Visual settling must not delay capture completion")
        }
    }

    func testEndpointIndicatorUsesActualTimerAndResetsForAudioAndTranscript() {
        var endpoint = LocalSpeechEndpoint()
        XCTAssertEqual(endpoint.progress(at: 100), 0)
        endpoint.updateTranscript("Coffee four euros", at: 10)
        XCTAssertEqual(endpoint.progress(at: 11.1), 0.5, accuracy: 0.001)
        endpoint.observeLevel(0.2, at: 11.1)
        XCTAssertEqual(endpoint.progress(at: 11.1), 0)
        XCTAssertFalse(endpoint.shouldFinish(at: 12))
        endpoint.updateTranscript("Coffee five euros", at: 12)
        XCTAssertEqual(endpoint.progress(at: 12), 0)
        XCTAssertEqual(endpoint.progress(at: 14.3), 1)
        XCTAssertTrue(endpoint.shouldFinish(at: 14.3))
        endpoint.updateTranscript("Flowers and", at: 15)
        XCTAssertEqual(endpoint.progress(at: 17.25), 0.5, accuracy: 0.001)
        XCTAssertFalse(endpoint.shouldFinish(at: 17.25))
    }

    func testEndpointFeedbackClearsWhenCaptureStopsAndCloudIgnoresIt() {
        let vm = VoiceModeViewModel()
        vm.open(provider: .appleLocal)
        vm.handleVoiceEvent(.microphoneStarted)
        vm.handleVoiceEvent(.localEndpointProgress(0.6))
        XCTAssertEqual(vm.localEndpointProgress, 0.6)
        vm.handleVoiceEvent(.microphoneStopped)
        vm.handleVoiceEvent(.localEndpointProgress(0.9))
        XCTAssertEqual(vm.localEndpointProgress, 0)
        vm.handleVoiceEvent(.microphoneStarted)
        vm.handleVoiceEvent(.localEndpointProgress(.nan))
        XCTAssertEqual(vm.localEndpointProgress, 0)
        vm.handleVoiceEvent(.localEndpointProgress(0.8))
        vm.suspendLocalRecording()
        XCTAssertEqual(vm.localEndpointProgress, 0)
        XCTAssertFalse(vm.microphoneIsActive)
        vm.open(provider: .openAI)
        vm.handleVoiceEvent(.microphoneStarted)
        vm.handleVoiceEvent(.localEndpointProgress(0.7))
        XCTAssertEqual(vm.localEndpointProgress, 0)
        vm.cancelSession()
    }

    func testAutomaticEndpointWaitsForQuietAndStableTranscript() {
        var endpoint = LocalSpeechEndpoint()
        XCTAssertFalse(endpoint.shouldFinish(at: 100))
        endpoint.updateTranscript("Coffee four euros", at: 10)
        XCTAssertFalse(endpoint.shouldFinish(at: 12))
        endpoint.observeLevel(0.3, at: 12)
        XCTAssertFalse(endpoint.shouldFinish(at: 14))
        endpoint.updateTranscript("Coffee four euros fifty", at: 14)
        XCTAssertFalse(endpoint.shouldFinish(at: 16))
        XCTAssertTrue(endpoint.shouldFinish(at: 16.3))
        endpoint.updateTranscript("Coffee four euros fifty", at: 16.4)
        XCTAssertTrue(endpoint.shouldFinish(at: 16.5), "Identical partial callbacks must not keep postponing the endpoint")
        endpoint.updateTranscript("  ", at: 17)
        XCTAssertFalse(endpoint.shouldFinish(at: 30))
    }

    func testEndpointAllowsSentencePausesAndContinuationsInBothLanguages() {
        for text in ["Coffee four euros and", "Kaffee vier Euro und", "Blumen für", "Flowers for"] {
            var endpoint = LocalSpeechEndpoint()
            endpoint.updateTranscript(text, at: 10)
            XCTAssertFalse(endpoint.shouldFinish(at: 13), text)
            XCTAssertTrue(endpoint.shouldFinish(at: 14.6), text)
            endpoint.updateTranscript(text + " twelve", at: 14)
            XCTAssertFalse(endpoint.shouldFinish(at: 15), text)
            XCTAssertTrue(endpoint.shouldFinish(at: 16.3), text)
        }
    }

    func testAutomaticTurnResumesExactlyOnceWithCurrentWorkspace() async {
        var services: [StubVoiceService] = []
        let vm = VoiceModeViewModel(serviceFactory: { _ in
            let service = StubVoiceService(); services.append(service); return service
        })
        vm.open(provider: .appleLocal)
        vm.drafts = [draft("coffee", "Coffee", 4)]
        vm.startSession()
        for _ in 0..<20 { await Task.yield() }
        for _ in 0..<3 {
            let current = services.last!
            let oldCallback = current.onEvent
            current.onEvent?(.localTranscript("Coffee five euros"))
            current.finishTurn()
            XCTAssertFalse(vm.microphoneIsActive)
            XCTAssertEqual(vm.phase, .thinking)
            XCTAssertTrue(vm.localShouldListen)
            current.onEvent?(.localTurnReady)
            oldCallback?(.localTurnReady)
            oldCallback?(.error("Old turn failed"))
            for _ in 0..<20 { await Task.yield() }
            XCTAssertTrue(vm.microphoneIsActive)
            XCTAssertTrue(vm.localTranscript.isEmpty)
            XCTAssertEqual(vm.drafts.map(\.id), ["coffee"])
            XCTAssertTrue(services.last?.workspaceContext?.contains("coffee") == true)
        }
        XCTAssertEqual(services.count, 4)
        vm.cancelSession()
        services.last?.onEvent?(.localTurnReady)
        XCTAssertFalse(vm.isPresented)
        XCTAssertFalse(vm.microphoneIsActive)
    }

    func testPauseDuringProcessingControlsAutomaticResumeAndReview() async {
        let service = StubVoiceService()
        let vm = VoiceModeViewModel(serviceFactory: { _ in service })
        vm.open(provider: .appleLocal)
        vm.drafts = [draft("coffee", "Coffee", 4)]
        vm.startSession()
        for _ in 0..<20 { await Task.yield() }
        service.finishTurn()
        vm.toggleLocalRecording()
        XCTAssertFalse(vm.localShouldListen)
        service.onEvent?(.localTurnReady)
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertFalse(vm.microphoneIsActive)
        XCTAssertTrue(vm.canEndSession)
        vm.toggleLocalRecording()
        for _ in 0..<20 { await Task.yield() }
        vm.pauseLocalForReview()
        XCTAssertFalse(vm.localShouldListen)
        service.onEvent?(.localTurnReady)
        XCTAssertTrue(vm.canSaveDrafts)
        XCTAssertTrue(vm.canEndSession)
        XCTAssertFalse(vm.microphoneIsActive)
        vm.cancelSession()
    }

    func testBackgroundDuringProcessingAndDraftLimitPreventAutomaticResume() async {
        var services: [StubVoiceService] = []
        let vm = VoiceModeViewModel(serviceFactory: { _ in
            let service = StubVoiceService(); services.append(service); return service
        })
        vm.open(provider: .appleLocal)
        vm.drafts = [draft("coffee", "Coffee", 4)]
        vm.startSession()
        for _ in 0..<20 { await Task.yield() }
        let old = services.last!.onEvent
        services.last!.finishTurn()
        vm.suspendLocalRecording()
        old?(.localTurnReady)
        XCTAssertEqual(vm.phase, .error)
        XCTAssertFalse(vm.localShouldListen)
        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(vm.drafts.map(\.id), ["coffee"])
        vm.restartSession()
        for _ in 0..<20 { await Task.yield() }
        vm.drafts = (0..<10).map { draft("\($0)", "Coffee", 4) }
        services.last!.finishTurn()
        services.last!.onEvent?(.localTurnReady)
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertFalse(vm.localShouldListen)
        XCTAssertEqual(services.count, 2)
        vm.cancelSession()
    }

    func testEmptyFinishedTurnAndResumeChoiceDuringProcessing() async {
        var services: [StubVoiceService] = []
        let vm = VoiceModeViewModel(serviceFactory: { _ in
            let service = StubVoiceService(); services.append(service); return service
        })
        vm.open(provider: .appleLocal)
        vm.startSession()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(vm.localTranscript.isEmpty)
        services.last!.finishTurn()
        vm.toggleLocalRecording()
        XCTAssertFalse(vm.localShouldListen)
        vm.toggleLocalRecording()
        XCTAssertTrue(vm.localShouldListen)
        services.last!.onEvent?(.localTurnReady)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(services.count, 2)
        XCTAssertTrue(vm.microphoneIsActive)
        XCTAssertTrue(vm.drafts.isEmpty)
        XCTAssertTrue(vm.errorMessage.isEmpty)
        vm.toggleLocalRecording()
        services.last!.onEvent?(.localTurnReady)
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertFalse(vm.localShouldListen)
        vm.suspendLocalRecording()
        XCTAssertEqual(vm.phase, .idle, "An already paused session stays paused in the background")
        vm.cancelSession()
    }

    func testRecordingIgnoresStartupCategoryChangesAndInterruptionEnd() {
        for reason in [AVAudioSession.RouteChangeReason.categoryChange, .override, .wakeFromSleep, .unknown] {
            XCTAssertFalse(LocalRecordingLifecycle.shouldInterrupt(Notification(
                name: AVAudioSession.routeChangeNotification,
                userInfo: [AVAudioSessionRouteChangeReasonKey: NSNumber(value: reason.rawValue)])))
        }
        XCTAssertFalse(LocalRecordingLifecycle.shouldInterrupt(Notification(
            name: AVAudioSession.interruptionNotification,
            userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue)])))
        XCTAssertFalse(LocalRecordingLifecycle.shouldInterrupt(Notification(name: AVAudioSession.interruptionNotification)))
    }

    func testRecordingStillStopsForRealInterruptionsAndRouteLoss() {
        XCTAssertTrue(LocalRecordingLifecycle.shouldInterrupt(Notification(
            name: AVAudioSession.interruptionNotification,
            userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)])))
        for reason in [AVAudioSession.RouteChangeReason.oldDeviceUnavailable, .newDeviceAvailable,
                       .noSuitableRouteForCategory, .routeConfigurationChange] {
            XCTAssertTrue(LocalRecordingLifecycle.shouldInterrupt(Notification(
                name: AVAudioSession.routeChangeNotification,
                userInfo: [AVAudioSessionRouteChangeReasonKey: NSNumber(value: reason.rawValue)])))
        }
        for name in [Notification.Name.AVAudioEngineConfigurationChange,
                     AVAudioSession.mediaServicesWereLostNotification,
                     AVAudioSession.mediaServicesWereResetNotification,
                     UIApplication.didEnterBackgroundNotification] {
            XCTAssertTrue(LocalRecordingLifecycle.shouldInterrupt(Notification(name: name)))
        }
    }

    func testLocalRecoveryAndRepeatedTurnsRetainDraftsAndIgnoreOldCallbacks() async {
        var services: [StubVoiceService] = []
        let vm = VoiceModeViewModel(serviceFactory: { _ in
            let service = StubVoiceService()
            services.append(service)
            return service
        })
        vm.open(provider: .appleLocal)
        vm.drafts = [draft("coffee", "Coffee", 4)]
        vm.startSession()
        for _ in 0..<20 { await Task.yield() }
        for _ in 0..<3 {
            let active = services.last!
            let stale = active.onEvent
            active.onEvent?(.error(loc("VoiceAudioInterrupted")))
            XCTAssertEqual(vm.phase, .error)
            XCTAssertEqual(vm.drafts.map(\.id), ["coffee"])
            vm.restartSession()
            for _ in 0..<20 { await Task.yield() }
            stale?(.error("stale interruption"))
            XCTAssertTrue(vm.microphoneIsActive)
            XCTAssertNotEqual(vm.phase, .error)
            vm.toggleLocalRecording()
            XCTAssertEqual(services.last?.finishedTurns, 1)
            services.last?.onEvent?(.listeningStopped)
            services.last?.onEvent?(.localTurnReady)
            vm.toggleLocalRecording()
            for _ in 0..<20 { await Task.yield() }
            XCTAssertTrue(vm.microphoneIsActive)
            XCTAssertEqual(vm.drafts.map(\.id), ["coffee"])
        }
        vm.cancelSession()
    }

    private var savedSettings: Data?
    override func setUp() async throws {
        savedSettings = UserDefaults.standard.data(forKey: VoiceSettings.storageKey)
        UserDefaults.standard.removeObject(forKey: VoiceSettings.storageKey)
    }
    override func tearDown() async throws {
        if let savedSettings { UserDefaults.standard.set(savedSettings, forKey: VoiceSettings.storageKey) }
        else { UserDefaults.standard.removeObject(forKey: VoiceSettings.storageKey) }
    }

    func testNewInstallDefaultsToLocalWithoutEnablingCapture() {
        let settings = VoiceSettings.default
        XCTAssertEqual(settings.provider, .appleLocal)
        XCTAssertFalse(settings.isReady)
    }

    func testLegacyCloudChoiceAndConsentArePreserved() throws {
        let data = Data(#"{"enabled":true,"apiKeySuffix":"1234","verifiedAt":1000,"consentVersion":1,"consentedAt":1000}"#.utf8)
        let settings = try JSONDecoder().decode(VoiceSettings.self, from: data)
        XCTAssertEqual(settings.provider, .openAI)
        XCTAssertTrue(settings.isReady)
    }

    func testLocalEnablesWithoutAnyAPIKeyAndPersistsAcrossLaunch() {
        let vm = SettingsViewModel(availabilityProvider: { .available })
        vm.acceptVoiceConsent()
        vm.voiceEnabled = true
        XCTAssertTrue(vm.voiceSettings.isReady)
        XCTAssertFalse(vm.hasSavedVoiceAPIKey)
        XCTAssertFalse(vm.voiceSettings.isVerified)
        let reloaded = SettingsViewModel(availabilityProvider: { .available })
        XCTAssertEqual(reloaded.voiceSettings.provider, .appleLocal)
        XCTAssertTrue(reloaded.voiceSettings.isReady)
    }

    func testLocalRequiresConsentEvenWhenAvailable() {
        let vm = SettingsViewModel(availabilityProvider: { .available })
        vm.voiceEnabled = true
        XCTAssertFalse(vm.voiceSettings.isReady)
    }

    func testUnavailableLocalCannotEnableAndNeverSelectsCloud() {
        for availability in [LocalVoiceAvailability.needsOS, .deviceNotEligible, .intelligenceDisabled,
                             .modelNotReady, .unsupportedLanguage, .speechUnavailable] {
            let vm = SettingsViewModel(availabilityProvider: { availability })
            vm.acceptVoiceConsent()
            vm.voiceEnabled = true
            XCTAssertFalse(vm.voiceSettings.isReady)
            XCTAssertEqual(vm.voiceSettings.provider, .appleLocal)
        }
    }

    func testAvailabilityIsRecheckedWhenEnabling() {
        var availability = LocalVoiceAvailability.available
        let vm = SettingsViewModel(availabilityProvider: { availability })
        vm.acceptVoiceConsent()
        availability = .modelNotReady
        vm.voiceEnabled = true
        XCTAssertFalse(vm.voiceSettings.isReady)
        availability = .available
        vm.voiceEnabled = true
        XCTAssertTrue(vm.voiceSettings.isReady)
    }

    func testChangingProviderRevokesConsentAndRequiresCloudKey() {
        let vm = SettingsViewModel(availabilityProvider: { .available })
        vm.acceptVoiceConsent()
        vm.voiceEnabled = true
        vm.selectProvider(.openAI)
        XCTAssertFalse(vm.hasVoiceConsent)
        XCTAssertFalse(vm.voiceSettings.enabled)
        XCTAssertFalse(vm.canEnableVoice)
        vm.acceptVoiceConsent()
        vm.voiceEnabled = true
        XCTAssertFalse(vm.voiceSettings.isReady)
        vm.selectProvider(.appleLocal)
        XCTAssertFalse(vm.hasVoiceConsent)
        XCTAssertFalse(vm.voiceSettings.isReady)
    }

    func testMissingCloudKeyDoesNotDisableLocalMode() {
        let vm = SettingsViewModel(availabilityProvider: { .available })
        vm.acceptVoiceConsent()
        vm.voiceEnabled = true
        vm.reconcileStoredAPIKey()
        XCTAssertTrue(vm.voiceSettings.isReady)
    }

    func testLocalSettingsRoundTrip() throws {
        var settings = VoiceSettings.default
        settings.enabled = true
        settings.consentVersion = VoiceSettings.currentConsentVersion
        settings.consentedAt = Date()
        let decoded = try JSONDecoder().decode(VoiceSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.provider, .appleLocal)
        XCTAssertTrue(decoded.isReady)
    }

    func testOnlyLocalServiceIsCreatedAndFailureNeverFallsBack() async {
        var providers: [VoiceProvider] = []
        let local = StubVoiceService()
        local.connectError = LocalVoiceError(message: "Unavailable offline")
        let vm = VoiceModeViewModel(serviceFactory: { provider in
            providers.append(provider)
            return local
        })
        vm.open(provider: .appleLocal)
        vm.startSession()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(providers, [.appleLocal])
        XCTAssertEqual(vm.phase, .error)
        XCTAssertEqual(vm.errorMessage, "Unavailable offline")
        vm.cancelSession()
    }

    func testLocalRecordingMustFinishBeforeSavingAndClosedCallbacksAreIgnored() async {
        let local = StubVoiceService()
        let vm = VoiceModeViewModel(serviceFactory: { _ in local })
        vm.open(provider: .appleLocal)
        vm.startSession()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(vm.microphoneIsActive)
        XCTAssertFalse(vm.canEndSession)
        vm.toggleLocalRecording()
        XCTAssertEqual(local.finishedTurns, 1)
        XCTAssertEqual(vm.phase, .thinking)
        local.onEvent?(.localTurnReady)
        XCTAssertTrue(vm.canEndSession)
        let stale = local.onEvent
        vm.cancelSession()
        vm.open(provider: .appleLocal)
        stale?(.localTranscript("Must not leak from a closed session"))
        XCTAssertTrue(vm.localTranscript.isEmpty)
        XCTAssertFalse(vm.microphoneIsActive)
        vm.cancelSession()
    }

    @available(iOS 26.0, *)
    func testLocalMergeAddsCorrectsAndPreservesUnchangedExpenses() throws {
        let vm = VoiceModeViewModel()
        vm.open(provider: .appleLocal)
        vm.drafts = [draft("coffee", "Coffee", 4), draft("flowers", "Flowers", 12)]
        let output = LocalExpenseInterpretation(requestSummary: "", updates: [
            LocalExpenseUpdate(existingID: "coffee", title: "Coffee", amountEvidence: "4.5", dateEvidence: "", splitEvidence: ""),
            LocalExpenseUpdate(existingID: "", title: "Train", amountEvidence: "20", dateEvidence: "", splitEvidence: "partner 8 euros")
        ], removedIDs: [], clarificationQuestion: "")
        let payload = try AppleExpenseInterpreter.payload(output, transcript: "Coffee was 4.5 and train 20 partner 8 euros", context: vm.resumeWorkspaceContext())
        vm.handleVoiceEvent(.workspaceSync(payload))
        XCTAssertEqual(vm.drafts.map(\.title), ["Coffee", "Flowers", "Train"])
        XCTAssertEqual(vm.drafts.map(\.amount), [4.5, 12, 20])
        XCTAssertEqual(vm.drafts.last?.partnerShare, 8)
        XCTAssertTrue(vm.canSaveDrafts)
        vm.cancelSession()
    }

    @available(iOS 26.0, *)
    func testMissingAmountRequiresClarificationAndCannotSave() throws {
        let output = LocalExpenseInterpretation(requestSummary: "", updates: [
            LocalExpenseUpdate(existingID: "", title: "Coffee", amountEvidence: "", dateEvidence: "", splitEvidence: "")
        ], removedIDs: [], clarificationQuestion: "")
        let payload = try AppleExpenseInterpreter.payload(output, transcript: "Coffee", context: nil)
        XCTAssertEqual(payload.expenses.first?.missingFields, [.amount])
        XCTAssertFalse(payload.expenses[0].draft.isReadyForSaving)
        XCTAssertFalse(payload.clarificationQuestion.isEmpty)
    }

    @available(iOS 26.0, *)
    func testInvalidGeneratedValuesAndUnknownIDsAreRejected() {
        let invalid: [LocalExpenseUpdate] = [
            .init(existingID: "", title: "Coffee", amountEvidence: "-4", dateEvidence: "", splitEvidence: ""),
            .init(existingID: "", title: "Coffee", amountEvidence: "999999999999", dateEvidence: "", splitEvidence: ""),
            .init(existingID: "", title: "Coffee", amountEvidence: "4", dateEvidence: "2026-02-30", splitEvidence: ""),
            .init(existingID: "", title: "Coffee", amountEvidence: "4", dateEvidence: "", splitEvidence: "partner 101 percent"),
            .init(existingID: "", title: "Coffee", amountEvidence: "4", dateEvidence: "", splitEvidence: "partner 5 euros"),
            .init(existingID: "invented", title: "Coffee", amountEvidence: "4", dateEvidence: "", splitEvidence: "")
        ]
        for update in invalid {
            let transcript = ["Coffee", update.amountEvidence, update.dateEvidence, update.splitEvidence].joined(separator: " ")
            XCTAssertThrowsError(try AppleExpenseInterpreter.payload(
                .init(requestSummary: "", updates: [update], removedIDs: [], clarificationQuestion: ""), transcript: transcript, context: nil))
        }
    }

    func testSpokenMoneyAndDatesUseSourceValuesInsteadOfGeneratedArithmetic() {
        for (phrase, expected) in [("four euros fifty", 4.5), ("vier Euro fünfzig", 4.5), ("twelve euros", 12.0),
                                    ("zwölf Euro", 12.0), ("vier fünfzig", 4.5), ("84,30", 84.3), ("1,234.56", 1234.56),
                                    ("1.234,56", 1234.56), ("1.234 Euro", 1234.0), ("1,234 euros", 1234.0), ("my partner owes 20 euros", 20.0), ("25 Prozent", 25.0)] {
            XCTAssertEqual(LocalSpokenValue.amount(phrase), expected, phrase)
        }
        XCTAssertNil(LocalSpokenValue.amount("Coffee"))
        XCTAssertEqual(LocalSpokenValue.date("yesterday", today: "2026-09-27"), "2026-09-26")
        XCTAssertEqual(LocalSpokenValue.date("gestern", today: "2026-01-01"), "2025-12-31")
        XCTAssertNil(LocalSpokenValue.date("2026-02-30", today: "2026-09-27"))
    }

    @available(iOS 26.0, *)
    func testExplicitHalfAndAllSharesAndUnsupportedShareDoNotSilentlyDefault() throws {
        for (phrase, expected) in [("partner pays half", 50.0), ("Partner zahlt die Hälfte", 50.0), ("partner pays all", 100.0)] {
            let result = try AppleExpenseInterpreter.payload(.init(requestSummary: "", updates: [
                .init(existingID: "", title: "Coffee", amountEvidence: "4 euros", dateEvidence: "", splitEvidence: phrase)
            ], removedIDs: [], clarificationQuestion: ""), transcript: "Coffee 4 euros \(phrase)", context: nil)
            XCTAssertEqual(result.expenses.first?.splitValue, expected)
        }
        XCTAssertThrowsError(try AppleExpenseInterpreter.payload(.init(requestSummary: "", updates: [
            .init(existingID: "", title: "Coffee", amountEvidence: "4 euros", dateEvidence: "", splitEvidence: "partner pays most")
        ], removedIDs: [], clarificationQuestion: ""), transcript: "Coffee 4 euros partner pays most", context: nil))
    }

    @available(iOS 26.0, *)
    func testInventedPriceEvidenceCannotBecomeASavableExpense() throws {
        let output = LocalExpenseInterpretation(requestSummary: "Coffee", updates: [
            .init(existingID: "", title: "Coffee", amountEvidence: "four euros fifty", dateEvidence: "", splitEvidence: "")
        ], removedIDs: [], clarificationQuestion: "")
        let payload = try AppleExpenseInterpreter.payload(output, transcript: "Coffee", context: nil)
        XCTAssertNil(payload.expenses[0].amount)
        XCTAssertFalse(payload.expenses[0].draft.isReadyForSaving)
    }

    @available(iOS 26.0, *)
    func testSpokenRemovalAndInFlightManualRemovalAreRespected() throws {
        let vm = VoiceModeViewModel()
        vm.open(provider: .appleLocal)
        vm.drafts = [draft("coffee", "Coffee", 4), draft("flowers", "Flowers", 12)]
        let context = vm.resumeWorkspaceContext()
        let output = LocalExpenseInterpretation(requestSummary: "", updates: [], removedIDs: ["flowers"], clarificationQuestion: "")
        let payload = try AppleExpenseInterpreter.payload(output, transcript: "Remove flowers", context: context)
        vm.removeDraft(vm.drafts[0])
        vm.handleVoiceEvent(.workspaceSync(payload))
        XCTAssertTrue(vm.drafts.isEmpty)
        vm.cancelSession()
    }

    private func draft(_ id: String, _ title: String, _ amount: Double) -> VoiceExpenseDraft {
        VoiceExpenseDraft(id: id, title: title, amount: amount, dateISO: "2026-09-27", splitMode: .percent,
                          splitValue: 50, confidence: 1, missingFields: [])
    }
}

@MainActor
private final class StubVoiceService: VoiceSessionService {
    var onEvent: ((RealtimeVoiceServiceEvent) -> Void)?
    var connectError: Error?
    var finishedTurns = 0
    var workspaceContext: String?
    func connect(workspaceContext: String?) async throws {
        self.workspaceContext = workspaceContext
        if let connectError { throw connectError }
        onEvent?(.microphoneStarted)
    }
    func disconnect() {}
    func sendWorkspaceNote(_ text: String) {}
    func finishTurn() {
        finishedTurns += 1
        onEvent?(.microphoneStopped)
        onEvent?(.listeningStopped)
    }
}
