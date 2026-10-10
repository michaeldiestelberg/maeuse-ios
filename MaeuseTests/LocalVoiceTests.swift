import XCTest
import AVFoundation
import UIKit
import FoundationModels
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

    private struct LocalExpenseDate {
        enum Kind { case notMentioned, relativeDays, absolute, uncertain }
        let kind: Kind
        let isoDate: String?
        let dayOffset: Int?
    }
    @available(iOS 26.0, *)
    private struct LocalExpenseShare {
        let kind: LocalShareKind
        let value: Double?
        let otherValue: Double?
    }
    @available(iOS 26.0, *)
    private func update(_ number: Int = 0, title: String? = nil, amount: Double? = nil,
                        date: LocalExpenseDate = .init(kind: .notMentioned, isoDate: nil, dayOffset: nil),
                        share: LocalExpenseShare = .init(kind: .notMentioned, value: nil, otherValue: nil)) -> LocalExpenseUpdate {
        .init(action: number == 0 ? .add : .correct, expenseNumber: number, title: title, amount: amount,
            dateISO: date.isoDate, dayOffset: date.dayOffset, dateUnclear: date.kind == .uncertain,
            shareKind: share.kind, shareValue: share.value, secondShareValue: share.otherValue)
    }

    @available(iOS 26.0, *)
    private func result(_ updates: [LocalExpenseUpdate], context: String? = nil,
                        text: String = "Request", question: String = "", today: String = "2026-10-10") throws -> VoiceWorkspaceSyncPayload {
        try AppleExpenseInterpreter.payload(.init(updates: updates,
            clarificationQuestion: question), transcript: text, context: context, today: today,
            timeZone: TimeZone(identifier: "Europe/Berlin")!)
    }

    @available(iOS 26.0, *)
    func testLocalMergeAddsCorrectsAndPreservesUnchangedExpenses() throws {
        let vm = VoiceModeViewModel()
        vm.open(provider: .appleLocal)
        vm.drafts = [draft("coffee", "Coffee", 4), draft("flowers", "Flowers", 12)]
        let payload = try result([update(1, amount: 4.5), update(title: "Train", amount: 20,
            share: .init(kind: .partnerFixed, value: 8, otherValue: nil))], context: vm.resumeWorkspaceContext())
        vm.handleVoiceEvent(.workspaceSync(payload))
        XCTAssertEqual(vm.drafts.map(\.title), ["Coffee", "Flowers", "Train"])
        XCTAssertEqual(vm.drafts.map(\.amount), [4.5, 12, 20])
        XCTAssertEqual(vm.drafts.last?.partnerShare, 8)
        XCTAssertEqual(vm.drafts[1].dateISO, "2026-09-27")
        XCTAssertTrue(vm.canSaveDrafts)
        vm.cancelSession()
    }

    @available(iOS 26.0, *)
    func testTeslaStructuredInterpretationKeepsPriceDateAndUnassigned7030() throws {
        let sentence = "Tesla Supercharger hat mich 73 € gekostet das war bereits vor drei Tagen und ich würde es gern 7030 teilen"
        let payload = try result([update(title: "Tesla Supercharger", amount: 73,
            date: .init(kind: .relativeDays, isoDate: nil, dayOffset: -3),
            share: .init(kind: .unassignedRatio, value: 70, otherValue: 30))], text: sentence)
        let vm = VoiceModeViewModel(); vm.open(provider: .appleLocal)
        vm.handleVoiceEvent(.workspaceSync(payload))
        XCTAssertEqual(vm.drafts.first?.amount, 73)
        XCTAssertEqual(vm.drafts.first?.dateISO, "2026-10-07")
        XCTAssertNil(vm.drafts.first?.splitValue)
        XCTAssertTrue(vm.drafts.first?.splitIntent?.contains("70/30") == true)
        XCTAssertEqual(vm.drafts.first?.missingFields, [.split])
        XCTAssertFalse(vm.canSaveDrafts)
        XCTAssertTrue(vm.expensesForSaving().isEmpty)
        XCTAssertFalse(vm.clarificationQuestion.isEmpty)
        let context = try XCTUnwrap(vm.resumeWorkspaceContext())
        let jsonStart = try XCTUnwrap(context.firstIndex(of: "{"))
        let decoded = try JSONDecoder().decode(AppleExpenseInterpreter.Context.self, from: Data(context[jsonStart...].utf8))
        XCTAssertTrue(decoded.expenses[0].split_intent?.contains("70/30") == true)
        XCTAssertEqual(decoded.last_request, sentence)
        // Unrelated corrections must not erase the outstanding person assignment.
        vm.handleVoiceEvent(.workspaceSync(try result([update(1, title: "Tesla charging", amount: 74)], context: context)))
        XCTAssertFalse(vm.canSaveDrafts)
        XCTAssertTrue(vm.drafts.first?.splitIntent?.contains("70/30") == true)
        // Follow-up: "I pay 70" resolves the partner complement deterministically.
        vm.handleVoiceEvent(.workspaceSync(try result([update(1,
            share: .init(kind: .userPercent, value: 70, otherValue: nil))],
            context: vm.resumeWorkspaceContext(), text: "Ich übernehme 70 Prozent")))
        XCTAssertEqual(vm.drafts.first?.splitValue, 30)
        XCTAssertNil(vm.drafts.first?.splitIntent)
        XCTAssertEqual(vm.drafts.first?.amount, 74)
        XCTAssertEqual(vm.drafts.first?.dateISO, "2026-10-07")
        XCTAssertEqual(vm.expensesForSaving().first?.partnerShare, 22.2)
        XCTAssertTrue(vm.canSaveDrafts)
        vm.cancelSession()
    }

    @available(iOS 26.0, *)
    func testMissingAndUncertainSharesUse5050ButUnequalIntentDoesNot() throws {
        for kind in [LocalShareKind.notMentioned, .uncertain] {
            let payload = try result([update(title: "Coffee", amount: 4,
                share: .init(kind: kind, value: nil, otherValue: nil))])
            XCTAssertEqual(payload.expenses.first?.splitValue, 50)
            XCTAssertTrue(payload.expenses[0].draft.isReadyForSaving)
            XCTAssertTrue(payload.clarificationQuestion.isEmpty)
        }
        let equal = try result([update(title: "Coffee", amount: 4,
            share: .init(kind: .unassignedRatio, value: 50, otherValue: 50))])
        XCTAssertEqual(equal.expenses[0].splitValue, 50)
        XCTAssertTrue(equal.expenses[0].draft.isReadyForSaving)
        for kind in [LocalShareKind.partnerPercent, .userPercent] {
            let payload = try result([update(title: "Coffee", amount: 4,
                share: .init(kind: kind, value: 70, otherValue: nil))])
            XCTAssertEqual(payload.expenses.first?.splitValue, kind == .partnerPercent ? 70 : 30)
            XCTAssertTrue(payload.expenses[0].draft.isReadyForSaving)
        }
    }

    @available(iOS 26.0, *)
    func testUnclearFollowUpCannotEraseRecognizedUnequalIntent() throws {
        let vm = VoiceModeViewModel(); vm.open(provider: .appleLocal)
        vm.handleVoiceEvent(.workspaceSync(try result([update(title: "Tesla", amount: 73,
            share: .init(kind: .unassignedRatio, value: 70, otherValue: 30))])))
        vm.handleVoiceEvent(.workspaceSync(try result([update(1,
            share: .init(kind: .uncertain, value: nil, otherValue: nil))], context: vm.resumeWorkspaceContext())))
        XCTAssertTrue(vm.drafts[0].splitIntent?.contains("70/30") == true)
        XCTAssertNil(vm.drafts[0].splitValue); XCTAssertFalse(vm.canSaveDrafts)
        vm.handleVoiceEvent(.workspaceSync(try result([update(1,
            share: .init(kind: .partnerPercent, value: 50, otherValue: nil))], context: vm.resumeWorkspaceContext())))
        XCTAssertEqual(vm.drafts[0].splitValue, 50); XCTAssertTrue(vm.canSaveDrafts)
        vm.cancelSession()
    }

    @available(iOS 26.0, *)
    func testExplicitUnclearDateRemainsOpenUntilCorrectedAcrossTurns() throws {
        let vm = VoiceModeViewModel(); vm.open(provider: .appleLocal)
        vm.handleVoiceEvent(.workspaceSync(try result([update(title: "Coffee", amount: 4,
            date: .init(kind: .uncertain, isoDate: nil, dayOffset: nil))])))
        XCTAssertNil(vm.drafts[0].dateISO)
        XCTAssertEqual(vm.drafts[0].missingFields, [.date])
        XCTAssertFalse(vm.canSaveDrafts)
        vm.handleVoiceEvent(.workspaceSync(try result([update(1, amount: 5)], context: vm.resumeWorkspaceContext())))
        XCTAssertNil(vm.drafts[0].dateISO); XCTAssertFalse(vm.canSaveDrafts)
        vm.handleVoiceEvent(.workspaceSync(try result([update(1,
            date: .init(kind: .absolute, isoDate: "2026-10-08", dayOffset: nil))], context: vm.resumeWorkspaceContext())))
        XCTAssertEqual(vm.drafts[0].dateISO, "2026-10-08"); XCTAssertEqual(vm.drafts[0].amount, 5)
        XCTAssertTrue(vm.canSaveDrafts)
        vm.cancelSession()
    }

    @available(iOS 26.0, *)
    func testPartialDraftFollowUpRenameAndMultiplePurchasesPreserveCards() throws {
        let vm = VoiceModeViewModel(); vm.open(provider: .appleLocal)
        vm.handleVoiceEvent(.workspaceSync(try result([update(title: "Coffee"), update(title: "Flowers", amount: 12)])))
        XCTAssertEqual(vm.drafts.count, 2); XCTAssertFalse(vm.canSaveDrafts)
        XCTAssertEqual(vm.drafts[0].missingFields, [.amount])
        let id = vm.drafts[0].id
        vm.handleVoiceEvent(.workspaceSync(try result([update(1, amount: 4.5)], context: vm.resumeWorkspaceContext(), text: "Vier fünfzig")))
        XCTAssertEqual(vm.drafts[0].id, id); XCTAssertTrue(vm.canSaveDrafts)
        vm.handleVoiceEvent(.workspaceSync(try result([update(1, title: "Espresso")], context: vm.resumeWorkspaceContext())))
        XCTAssertEqual(vm.drafts.map(\.title), ["Espresso", "Flowers"])
        XCTAssertEqual(vm.drafts.map(\.amount), [4.5, 12])
        vm.cancelSession()
    }

    @available(iOS 26.0, *)
    func testAmbiguousTargetAsksWithoutMutatingExistingCards() throws {
        let vm = VoiceModeViewModel(); vm.open(provider: .appleLocal)
        vm.drafts = [draft("coffee", "Coffee", 4), draft("flowers", "Flowers", 12)]
        vm.handleVoiceEvent(.workspaceSync(try result([], context: vm.resumeWorkspaceContext(), question: "Welche Ausgabe?")))
        XCTAssertEqual(vm.drafts.map(\.id), ["coffee", "flowers"])
        XCTAssertEqual(vm.drafts.map(\.amount), [4,12])
        XCTAssertEqual(vm.clarificationQuestion, "Welche Ausgabe?")
        vm.cancelSession()
    }

    @available(iOS 26.0, *)
    func testInvalidGeneratedValuesAndUnknownTargetsAreRejectedAtomically() {
        for change in [update(title: "Coffee", amount: -4), update(title: "Coffee", amount: 1e12),
                       update(title: "Coffee", amount: 4, share: .init(kind: .partnerPercent, value: 101, otherValue: nil)),
                       update(1, title: "Unknown", amount: 4)] {
            XCTAssertThrowsError(try result([update(title: "Valid", amount: 5), change]))
        }
        XCTAssertThrowsError(try result([update(title: "Coffee", amount: .infinity)]))
    }

    @available(iOS 26.0, *)
    func testFixedShareArithmeticAndChangedPriceRequireValidDomainValues() throws {
        let payload = try result([update(title: "Dinner", amount: 73,
            share: .init(kind: .userFixed, value: 20, otherValue: nil))])
        XCTAssertEqual(payload.expenses.first?.splitValue, 53)
        let vm = VoiceModeViewModel(); vm.open(provider: .appleLocal)
        vm.handleVoiceEvent(.workspaceSync(payload))
        vm.handleVoiceEvent(.workspaceSync(try result([update(1, amount: 40)], context: vm.resumeWorkspaceContext())))
        XCTAssertEqual(vm.drafts[0].amount, 40); XCTAssertFalse(vm.canSaveDrafts)
        XCTAssertEqual(vm.drafts[0].missingFields, [.split])
        vm.handleVoiceEvent(.workspaceSync(try result([update(1,
            share: .init(kind: .partnerFixed, value: 10, otherValue: nil))], context: vm.resumeWorkspaceContext())))
        XCTAssertTrue(vm.canSaveDrafts)
        vm.cancelSession()
    }

    @available(iOS 26.0, *)
    func testInvalidCalendarDateKeepsRecognizedPriceAndAsksForDate() throws {
        let payload = try result([update(title: "Coffee", amount: 4,
            date: .init(kind: .absolute, isoDate: "2026-02-30", dayOffset: nil))])
        XCTAssertEqual(payload.expenses[0].amount, 4)
        XCTAssertNil(payload.expenses[0].dateISO)
        XCTAssertEqual(payload.expenses[0].missingFields, [.date])
        XCTAssertFalse(payload.expenses[0].draft.isReadyForSaving)
    }

    @available(iOS 26.0, *)
    func testOwnFixedShareWithMissingTotalResolvesDeterministicallyOnFollowUp() throws {
        let vm = VoiceModeViewModel(); vm.open(provider: .appleLocal)
        vm.handleVoiceEvent(.workspaceSync(try result([update(title: "Dinner",
            share: .init(kind: .userFixed, value: 20, otherValue: nil))])))
        XCTAssertEqual(vm.drafts[0].pendingUserFixedShare, 20)
        XCTAssertFalse(vm.canSaveDrafts)
        vm.handleVoiceEvent(.workspaceSync(try result([update(1, amount: 73)], context: vm.resumeWorkspaceContext())))
        XCTAssertEqual(vm.drafts[0].splitValue, 53)
        XCTAssertNil(vm.drafts[0].pendingUserFixedShare)
        XCTAssertNil(vm.drafts[0].splitIntent)
        XCTAssertTrue(vm.canSaveDrafts)
        vm.cancelSession()
    }

    @available(iOS 26.0, *)
    func testRelativeDatesUseCalendarAcrossLeapDayAndTimeZones() throws {
        for zone in ["Europe/Berlin", "America/Los_Angeles", "Pacific/Kiritimati"] {
            let value = try AppleExpenseInterpreter.payload(.init(updates: [
                update(title: "Coffee", amount: 4, date: .init(kind: .relativeDays, isoDate: nil, dayOffset: -1))
            ], clarificationQuestion: ""), transcript: "Yesterday", context: nil, today: "2024-03-01",
                timeZone: TimeZone(identifier: zone)!)
            XCTAssertEqual(value.expenses[0].dateISO, "2024-02-29", zone)
        }
    }

    @available(iOS 26.0, *)
    func testSpokenRemovalAndInFlightManualRemovalAreRespected() throws {
        let vm = VoiceModeViewModel(); vm.open(provider: .appleLocal)
        vm.drafts = [draft("coffee", "Coffee", 4), draft("flowers", "Flowers", 12)]
        var removal = update(2); removal.action = .remove
        let payload = try result([removal], context: vm.resumeWorkspaceContext())
        vm.removeDraft(vm.drafts[0]); vm.handleVoiceEvent(.workspaceSync(payload))
        XCTAssertTrue(vm.drafts.isEmpty)
        vm.cancelSession()
    }

    func testLiteralRatioTokensRequireUniqueSplitAndExactNumericBoundaries() {
        let pair = VoiceWorkspaceDomain.concatenatedPercentages("7030")
        XCTAssertEqual(pair?.0, 70); XCTAssertEqual(pair?.1, 30)
        XCTAssertEqual(VoiceWorkspaceDomain.concatenatedPercentages("9010")?.0, 90)
        XCTAssertNil(VoiceWorkspaceDomain.concatenatedPercentages("991"))
        XCTAssertNil(VoiceWorkspaceDomain.concatenatedPercentages("seventy thirty"))
        XCTAssertTrue(VoiceWorkspaceDomain.numericToken("7030", occursIn: "7030 teilen"))
        XCTAssertFalse(VoiceWorkspaceDomain.numericToken("70", occursIn: "7030 teilen"))
        XCTAssertFalse(VoiceWorkspaceDomain.numericToken("30", occursIn: "7030 teilen"))
        XCTAssertTrue(VoiceWorkspaceDomain.numericToken("9,80", occursIn: "Preis 9,80 Euro"))
        XCTAssertFalse(VoiceWorkspaceDomain.numericToken("80", occursIn: "Preis 9,80 Euro"))
    }

    @available(iOS 26.0, *)
    func testStructuredPlanMultiplePurchasesGetDomainDefaultsAndSharedRelativeDate() throws {
        let actions: [LocalPlanAction] = [
            .add(.init(title: "Coffee", amount: .init(euros: 4, cents: 50), date: .relativeDays(-1), share: .notMentioned)),
            .add(.init(title: "Flowers", amount: .init(euros: 12, cents: 0), date: .relativeDays(-1), share: .notMentioned))]
        let result = try AppleExpenseInterpreter.applyPlan(.init(actions: actions), to: [], transcript: "", today: "2026-09-27", timeZone: TimeZone(identifier: "Europe/Berlin")!)
        XCTAssertEqual(result.expenses.map(\.amount), [4.5, 12])
        XCTAssertEqual(result.expenses.map(\.dateISO), ["2026-09-26", "2026-09-26"])
        XCTAssertEqual(result.expenses.map(\.splitValue), [50, 50])
        XCTAssertEqual(Set(result.expenses.map(\.id)).count, 2)
        XCTAssertTrue(result.expenses.allSatisfy { $0.draft.isReadyForSaving })
    }

    @available(iOS 26.0, *)
    func testStructuredPlanRatioKeepsPriceAndDateUntilPersonClarification() throws {
        let initial = try AppleExpenseInterpreter.applyPlan(.init(actions: [.add(.init(title: "Tesla", amount: .init(euros: 73, cents: 0), date: .relativeDays(-3), share: .init(kind: .unassignedRatio, value: 70, secondValue: 30)))]), to: [], transcript: "", today: "2026-09-27", timeZone: .current)
        XCTAssertEqual(initial.expenses[0].amount, 73)
        XCTAssertEqual(initial.expenses[0].dateISO, "2026-09-24")
        XCTAssertTrue(initial.expenses[0].splitIntent?.contains("70/30") == true)
        XCTAssertFalse(initial.expenses[0].draft.isReadyForSaving)
        let fixed = try AppleExpenseInterpreter.applyPlan(.init(actions: [.edit(.init(expenseNumber: 1, title: nil, amount: nil, date: .notMentioned, share: .init(kind: .speakerPercent, value: 70, secondValue: 0)))]), to: initial.expenses, transcript: "", today: "2026-09-27", timeZone: .current)
        XCTAssertEqual(fixed.expenses[0].id, initial.expenses[0].id)
        XCTAssertEqual(fixed.expenses[0].splitValue, 30)
        XCTAssertEqual(fixed.expenses[0].dateISO, "2026-09-24")
        XCTAssertTrue(fixed.expenses[0].draft.isReadyForSaving)
    }

    @available(iOS 26.0, *)
    func testStructuredPlanInvalidTargetIsAtomicAndExistingCorrectionsKeepIDs() throws {
        let rows = [draft("coffee", "Coffee", 4).payload, draft("flowers", "Flowers", 12).payload]
        let edit = LocalPlanAction.edit(.init(expenseNumber: 1, title: nil, amount: .init(euros: 5, cents: 0), date: .notMentioned, share: .notMentioned))
        let result = try AppleExpenseInterpreter.applyPlan(.init(actions: [edit]), to: rows, transcript: "", today: "2026-09-27", timeZone: .current)
        XCTAssertEqual(result.expenses.map(\.id), ["coffee", "flowers"])
        XCTAssertEqual(result.expenses.map(\.amount), [5, 12])
        XCTAssertThrowsError(try AppleExpenseInterpreter.applyPlan(.init(actions: [edit, .remove(expenseNumber: 3)]), to: rows, transcript: "", today: "2026-09-27", timeZone: .current))
        XCTAssertEqual(rows.map(\.amount), [4, 12])
    }

    @available(iOS 26.0, *)
    func testStructuredPlanUnresolvedFieldDoesNotDiscardRecognizedPurchase() throws {
        let result = try AppleExpenseInterpreter.applyPlan(.init(actions: [.add(.init(title: "Entry", amount: .init(euros: 28, cents: 0), date: .notMentioned, share: .init(kind: .unresolved, value: 0, secondValue: 0, intent: "unclear contribution")))]), to: [], transcript: "", today: "2026-09-27", timeZone: .current)
        XCTAssertEqual(result.expenses[0].amount, 28)
        XCTAssertEqual(result.expenses[0].dateISO, "2026-09-27")
        XCTAssertTrue(result.expenses[0].missingFields.contains(.split))
        XCTAssertFalse(result.expenses[0].draft.isReadyForSaving)
    }

    @available(iOS 26.0, *)
    func testStructuredPlanInvalidSharePreservesMoneyAndBlocksSaving() throws {
        for share in [LocalPlanShare(kind: .speakerEuros, value: 29, secondValue: 0),
                      LocalPlanShare(kind: .partnerPercent, value: 101, secondValue: 0),
                      LocalPlanShare(kind: .unassignedRatio, value: 0, secondValue: 0)] {
            let result = try AppleExpenseInterpreter.applyPlan(.init(actions: [.add(.init(title: "Entry", amount: .init(euros: 28, cents: 0), date: .relativeDays(-2), share: share))]), to: [], transcript: "", today: "2026-09-27", timeZone: .current)
            XCTAssertEqual(result.expenses[0].amount, 28)
            XCTAssertEqual(result.expenses[0].dateISO, "2026-09-25")
            XCTAssertFalse(result.expenses[0].draft.isReadyForSaving)
            XCTAssertTrue(result.expenses[0].missingFields.contains(.split))
        }
    }

    @available(iOS 26.0, *)
    func testPriceWitnessCannotReuseRatioOrInventCurrency() {
        let text = "Charging 73 €; split 7030"
        XCTAssertNil(AppleExpenseInterpreter.validatedMoneyQuote(.init(priceText: "7030", currencyText: "€"), in: text))
        XCTAssertNil(AppleExpenseInterpreter.validatedMoneyQuote(.init(priceText: "7030 €", currencyText: "€"), in: text))
        XCTAssertEqual(AppleExpenseInterpreter.validatedMoneyQuote(.init(priceText: "73 €", currencyText: "€"), in: text), "73 €")
        XCTAssertNil(AppleExpenseInterpreter.purchaseQuote("30 €", in: "7030 €"))
        XCTAssertNil(AppleExpenseInterpreter.purchaseQuote("40 €", in: "82,40 €"))
        XCTAssertEqual(AppleExpenseInterpreter.literalMoney("7030")?.euros, 7030)
        XCTAssertEqual(AppleExpenseInterpreter.literalMoney("7030")?.cents, 0)
        XCTAssertEqual(AppleExpenseInterpreter.literalMoney("82,40")?.euros, 82)
        XCTAssertEqual(AppleExpenseInterpreter.literalMoney("82,40")?.cents, 40)
        XCTAssertNil(AppleExpenseInterpreter.literalMoney("7.030"), "Ambiguous grouping is never silently a decimal amount")
        XCTAssertNil(AppleExpenseInterpreter.literalMoney("-73"))
        XCTAssertEqual(VoiceWorkspaceDomain.literalNumericTokens(in: "73 €; 7030 teilen."), ["73", "7030"])
        XCTAssertEqual(VoiceWorkspaceDomain.literalNumericTokens(in: "82,40 € und 19.80 Euro"), ["82,40", "19.80"])
        XCTAssertEqual(VoiceWorkspaceDomain.literalNumericTokens(in: "-70 zu 30"), ["-70", "30"])
    }

    @available(iOS 26.0, *)
    func testUnclassifiedConcreteShareCannotBecomeEqualDefault() throws {
        let share = AppleExpenseInterpreter.unresolvedShare("7030 teilen", recognizedIntent: true)
        XCTAssertEqual(share.kind, .unresolved)
        let row = try AppleExpenseInterpreter.applyPlan(.init(actions: [.add(.init(title: "Charging", amount: .init(euros: 73, cents: 0), date: .relativeDays(-3), share: share))]), to: [], transcript: "", today: "2026-10-10", timeZone: .current).expenses[0]
        XCTAssertEqual(row.amount, 73); XCTAssertEqual(row.dateISO, "2026-10-07")
        XCTAssertNotEqual(row.splitValue, 50); XCTAssertFalse(row.draft.isReadyForSaving)
        let absent = AppleExpenseInterpreter.unresolvedShare("not sure about splitting", recognizedIntent: false)
        XCTAssertEqual(absent.kind, .notMentioned)
    }

    @available(iOS 26.0, *)
    func testUnsupportedExplicitPriceCorrectionRetainsOldAmountButBlocksSave() throws {
        let result = try AppleExpenseInterpreter.applyPlan(.init(actions: [.edit(.init(expenseNumber: 1, title: nil, amount: .init(euros: 0, cents: 0), date: .notMentioned, share: .notMentioned))]), to: [draft("coffee", "Coffee", 4).payload], transcript: "", today: "2026-10-10", timeZone: .current)
        XCTAssertEqual(result.expenses[0].amount, 4)
        XCTAssertTrue(result.expenses[0].missingFields.contains(.amount))
        XCTAssertFalse(result.expenses[0].draft.isReadyForSaving)
    }

    @available(iOS 26.0, *)
    func testLiteralRatioWitnessCannotTreatPricesAsShares() {
        XCTAssertTrue(AppleExpenseInterpreter.hasLiteralRatioWitness("7030 teilen"))
        XCTAssertTrue(AppleExpenseInterpreter.hasLiteralRatioWitness("60 zu 40"))
        XCTAssertFalse(AppleExpenseInterpreter.hasLiteralRatioWitness("milk 1.90 euros"))
        XCTAssertFalse(AppleExpenseInterpreter.hasLiteralRatioWitness("73 €"))
        XCTAssertFalse(AppleExpenseInterpreter.hasLiteralRatioWitness("991"))
    }

    @available(iOS 26.0, *)
    func testDiagnosisExcludesProviderDescriptionsAndPrivateFinancialData() {
        var now = 10.0
        let trace = LocalVoiceTrace(language: "de-DE", modelVariant: "test-variant", availability: "available", referenceDate: "2026-10-10", clock: { now })
        trace.begin("LocalMoneySource"); now = 10.250; trace.endStep()
        let error = NSError(domain: "com.apple.FoundationModels", code: 1032,
            userInfo: [NSLocalizedDescriptionKey: "PRIVATE_TRANSCRIPT €73 Tesla"])
        trace.failed(LocalVoiceIssue.classify(error))
        XCTAssertEqual(trace.snapshot.elapsedMilliseconds, 250)
        XCTAssertTrue(trace.snapshot.exportText.contains("1032"))
        XCTAssertTrue(trace.snapshot.exportText.contains("test-variant"))
        XCTAssertFalse(trace.snapshot.exportText.contains("PRIVATE_TRANSCRIPT"))
        XCTAssertFalse(trace.snapshot.exportText.contains("Tesla"))
        XCTAssertFalse(trace.snapshot.exportText.contains("€73"))
        XCTAssertTrue(trace.snapshot.isTerminal)
    }

    @available(iOS 27.0, *)
    func testSDKTypedFailuresHaveSpecificCategoriesWithoutPrivateDescriptions() {
        let privateText = "PRIVATE €73 Tesla"
        let errors: [(Error, LocalVoiceIssue.Category)] = [
            (LanguageModelError.timeout(.init(debugDescription: privateText)), .timeout),
            (LanguageModelError.guardrailViolation(.init(debugDescription: privateText)), .guardrail),
            (LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: privateText)), .rateLimited),
            (LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: privateText)), .context),
            (LanguageModelSession.Error.concurrentRequests, .busy)
        ]
        for (error, expected) in errors {
            let issue = LocalVoiceIssue.classify(error)
            XCTAssertEqual(issue.category, expected)
            let trace = LocalVoiceTrace(language: "de-DE", modelVariant: "test", availability: "available", referenceDate: "2026-10-10")
            trace.failed(issue)
            XCTAssertFalse(trace.snapshot.exportText.contains(privateText))
        }
    }

    func testLastCompletedDiagnosisSurvivesAutomaticNextTurnAndClearsOnClose() {
        let vm = VoiceModeViewModel(); vm.open(provider: .appleLocal)
        let trace = LocalVoiceTrace(language: "de-DE", modelVariant: "test", availability: "available", referenceDate: "2026-10-10")
        trace.completed(); vm.handleVoiceEvent(.localDiagnostic(trace.snapshot))
        let previousID = trace.snapshot.turnID
        let next = LocalVoiceTrace(language: "de-DE", modelVariant: "test", availability: "available", referenceDate: "2026-10-10")
        vm.handleVoiceEvent(.localDiagnostic(next.snapshot))
        XCTAssertEqual(vm.displayedLocalDiagnostic?.turnID, previousID)
        vm.cancelSession(); XCTAssertNil(vm.localDiagnostic); XCTAssertNil(vm.completedLocalDiagnostic)
    }

    func testProductionProcessingBoundaryTimeoutPreservesDraftAndLastStage() async {
        let vm = VoiceModeViewModel(); vm.open(provider: .appleLocal); vm.suspendLocalRecording()
        vm.drafts = [draft("existing", "Existing", 12)]
        let failed = expectation(description: "production processing deadline")
        let service = AppleLocalVoiceService(processingTimeout: .milliseconds(20)) { _, _, trace in
            trace?.begin("LocalMoneySource")
            try await Task.sleep(for: .seconds(2))
            return VoiceWorkspaceSyncPayload(userUnderstanding: "", clarificationQuestion: "", expenses: [], changedExpenseIDs: [], removedExpenseIDs: [])
        }
        service.onEvent = { event in
            vm.handleVoiceEvent(event)
            if case .error = event { failed.fulfill() }
        }
        service.processRecognizedText("PRIVATE_TRANSCRIPT", workspaceContext: vm.resumeWorkspaceContext(), completion: "quiet-endpoint/recognition-fallback")
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(vm.phase, .error); XCTAssertEqual(vm.drafts.map(\.id), ["existing"])
        XCTAssertEqual(vm.errorMessage, loc("LocalModelTimeout"))
        XCTAssertEqual(vm.displayedLocalDiagnostic?.stage, "LocalMoneySource")
        XCTAssertEqual(vm.displayedLocalDiagnostic?.issue?.category, .timeout)
        XCTAssertEqual(vm.displayedLocalDiagnostic?.captureEnd, "quiet-endpoint/recognition-fallback")
        XCTAssertFalse(vm.displayedLocalDiagnostic?.exportText.contains("PRIVATE_TRANSCRIPT") ?? true)
        service.disconnect(); vm.cancelSession()
    }

    func testProductionProcessingBoundaryRecoveryAndCancellationIgnoreLateResult() async {
        var calls = 0
        var published: [Double] = []
        let completed = expectation(description: "three recovered production turns"); completed.expectedFulfillmentCount = 3
        let service = AppleLocalVoiceService { _, _, _ in
            calls += 1
            if calls == 1 {
                // Deliberately non-cooperative processor verifies identity checking too.
                try? await Task.sleep(for: .milliseconds(60))
            }
            return VoiceWorkspaceSyncPayload(userUnderstanding: "", clarificationQuestion: "", expenses: [self.draft("same", "Coffee", Double(calls)).payload], changedExpenseIDs: ["same"], removedExpenseIDs: [])
        }
        service.onEvent = { event in
            if case .workspaceSync(let value) = event { published.append(value.expenses[0].amount!) }
            if case .localTurnReady = event { completed.fulfill() }
        }
        service.processRecognizedText("stale", workspaceContext: nil)
        for _ in 0..<10 { await Task.yield() }
        service.disconnect()
        for index in 0..<3 {
            if index > 0 { service.disconnect() }
            service.processRecognizedText("next", workspaceContext: nil)
            for _ in 0..<30 { await Task.yield() }
        }
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(published.count, 3)
        XCTAssertFalse(published.contains(1), "Canceled old processing must never publish")
        service.disconnect()
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
