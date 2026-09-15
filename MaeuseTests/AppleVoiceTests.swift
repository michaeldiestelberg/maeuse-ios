import XCTest
import FoundationModels
@testable import Maeuse

@MainActor
final class AppleVoiceTests: XCTestCase {
    private let today = "2026-09-15"

    private func draft(_ id: String = "coffee", title: String = "Coffee", amount: Double? = 4.5) -> VoiceExpenseDraft {
        VoiceExpenseDraft(id: id, title: title, amount: amount, dateISO: today,
            splitMode: .percent, splitValue: 50, confidence: 1, missingFields: [])
    }

    private func apply(_ changes: [AppleExpenseMutation], to drafts: [VoiceExpenseDraft] = [], removed: Set<String> = []) throws -> VoiceWorkspaceSyncPayload {
        try AppleWorkspaceReducer.apply(AppleWorkspaceUpdate(understanding: "Request", clarification: "", mutations: changes),
            to: drafts, removedIDs: removed, todayISO: today, responseID: "response-1", makeID: { "new-expense" })
    }

    func testLegacySettingsRemainOpenAI() throws {
        let json = Data(#"{"enabled":true,"apiKeySuffix":"1234","verifiedAt":1,"consentVersion":1,"consentedAt":1}"#.utf8)
        let settings = try JSONDecoder().decode(VoiceSettings.self, from: json)
        XCTAssertEqual(settings.provider, .openAI)
        XCTAssertTrue(settings.isReady)
        XCTAssertFalse(settings.appleEnabled)
        XCTAssertFalse(settings.allowPrivateCloudCompute)
    }

    func testAppleSettingsNeedNoOpenAIKeyOrConsentAndRoundTrip() throws {
        var settings = VoiceSettings.default
        settings.provider = .apple
        settings.appleEnabled = true
        XCTAssertTrue(settings.isReady)
        XCTAssertFalse(settings.hasCurrentConsent)
        let decoded = try JSONDecoder().decode(VoiceSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.provider, .apple)
        XCTAssertTrue(decoded.isReady)
        settings.provider = .openAI
        XCTAssertFalse(settings.isReady)
    }

    func testSwitchingProvidersPreservesOpenAIConfiguration() throws {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: VoiceSettings.storageKey)
        defer { defaults.set(original, forKey: VoiceSettings.storageKey) }
        let vm = SettingsViewModel()
        vm.voiceSettings = VoiceSettings(apiKeySuffix: "1234", verifiedAt: Date(), enabled: true,
            consentVersion: 1, consentedAt: Date())
        vm.hasSavedVoiceAPIKey = true
        vm.appleAvailability = .init(canStart: true, messageKey: "AppleReady")
        vm.useAppleIntelligence = true
        vm.voiceEnabled = true
        XCTAssertTrue(vm.canUseVoice)
        vm.voiceEnabled = false
        XCTAssertTrue(vm.voiceSettings.hasCurrentConsent)
        vm.useAppleIntelligence = false
        XCTAssertTrue(vm.voiceEnabled)
        XCTAssertTrue(vm.canUseVoice)
        XCTAssertEqual(vm.voiceSettings.apiKeySuffix, "1234")
    }

    func testUnavailableAppleCannotEnableAndDoesNotFallBackToOpenAI() {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: VoiceSettings.storageKey)
        defer { defaults.set(original, forKey: VoiceSettings.storageKey) }
        let vm = SettingsViewModel()
        vm.voiceSettings = VoiceSettings(apiKeySuffix: "1234", verifiedAt: Date(), enabled: true,
            consentVersion: 1, consentedAt: Date())
        vm.useAppleIntelligence = true
        vm.appleAvailability = .init(canStart: false, messageKey: "AppleUnavailable")
        vm.voiceEnabled = true
        XCTAssertFalse(vm.voiceEnabled)
        XCTAssertFalse(vm.canUseVoice)
        XCTAssertTrue(vm.voiceSettings.enabled)
    }

    func testAddDefaultsAndTransportIdentityComeFromApp() throws {
        let result = try apply([.init(action: .add, title: "Blumen", amount: 12.5)])
        XCTAssertEqual(result.responseID, "response-1")
        let entry = try XCTUnwrap(result.expenses.first)
        XCTAssertEqual(entry.id, "new-expense")
        XCTAssertEqual(entry.dateISO, today)
        XCTAssertEqual(entry.splitMode, "percent")
        XCTAssertEqual(entry.splitValue, 50)
        XCTAssertTrue(entry.draft.isReadyForSaving)
    }

    func testMultipleExpensesGetIndependentAppIDs() throws {
        let update = AppleWorkspaceUpdate(understanding: "Coffee and flowers", clarification: "", mutations: [
            .init(action: .add, title: "Coffee", amount: 4.5),
            .init(action: .add, title: "Flowers", amount: 12)])
        let result = try AppleWorkspaceReducer.apply(update, to: [], todayISO: today, responseID: "two")
        XCTAssertEqual(result.expenses.map(\.title), ["Coffee", "Flowers"])
        XCTAssertEqual(Set(result.expenses.map(\.id)).count, 2)
        XCTAssertEqual(result.expenses.map(\.amount), [4.5, 12])
    }

    func testCorrectionKeepsIDsOrderAndUnrelatedFields() throws {
        let result = try apply([.init(action: .update, targetID: "coffee", amount: 5.75)],
            to: [draft("flowers", title: "Flowers", amount: 12), draft()])
        XCTAssertEqual(result.expenses.map(\.id), ["flowers", "coffee"])
        XCTAssertEqual(result.expenses.map(\.amount), [12, 5.75])
        XCTAssertEqual(result.expenses.last?.title, "Coffee")
        XCTAssertEqual(result.expenses.last?.dateISO, today)
    }

    func testManualDeletionWinsOverPendingCorrection() throws {
        let result = try apply([.init(action: .update, targetID: "coffee", amount: 7)],
            to: [draft("flowers")], removed: ["coffee"])
        XCTAssertEqual(result.expenses.map(\.id), ["flowers"])
    }

    func testUnknownCorrectionAndDuplicateTargetsAreRejectedAtomically() {
        XCTAssertThrowsError(try apply([.init(action: .add, title: "Tea", amount: 3),
            .init(action: .update, targetID: "missing", amount: 8)], to: [draft()]))
        XCTAssertThrowsError(try apply([.init(action: .update, targetID: "coffee", amount: 8),
            .init(action: .remove, targetID: "coffee")], to: [draft()]))
    }

    func testMissingAmountStaysUnsavableAndCanBeCompleted() throws {
        let added = try apply([.init(action: .add, title: "Coffee")])
        let incomplete = try XCTUnwrap(added.expenses.first?.draft)
        XCTAssertFalse(incomplete.isReadyForSaving)
        XCTAssertEqual(incomplete.missingFields, [.amount])
        let corrected = try apply([.init(action: .update, targetID: incomplete.id, amount: 4.5)], to: [incomplete])
        XCTAssertTrue(try XCTUnwrap(corrected.expenses.first).draft.isReadyForSaving)
    }

    func testRemoveDoesNotDropUnrelatedExpense() throws {
        let result = try apply([.init(action: .remove, targetID: "coffee")], to: [draft(), draft("tea")])
        XCTAssertEqual(result.expenses.map(\.id), ["tea"])
        XCTAssertEqual(result.removedExpenseIDs, ["coffee"])
    }

    func testInvalidAmountsDatesAndSharesAreRejected() {
        for amount in [-1.0, 0, 0.001, Double.nan, .infinity] {
            XCTAssertThrowsError(try apply([.init(action: .add, title: "Coffee", amount: amount)]))
        }
        for date in ["2026-02-30", "yesterday", "2026-9-1"] {
            XCTAssertThrowsError(try apply([.init(action: .add, title: "Coffee", amount: 4, dateISO: date)]))
        }
        XCTAssertThrowsError(try apply([.init(action: .add, title: "Coffee", amount: 4, splitValue: 101)]))
        XCTAssertThrowsError(try apply([.init(action: .add, title: "Coffee", amount: 4, splitMode: "fixed", splitValue: 5)]))
        XCTAssertThrowsError(try apply([.init(action: .update, targetID: "coffee", splitMode: "fixed")], to: [draft()]))
    }

    func testFixedShareAndRelativeDateResolvedByModelAreValidated() throws {
        let result = try apply([.init(action: .add, title: "Train", amount: 35,
            dateISO: "2026-09-14", splitMode: "fixed", splitValue: 12)])
        XCTAssertEqual(result.expenses.first?.draft.partnerShare, 12)
        XCTAssertEqual(result.expenses.first?.dateISO, "2026-09-14")
    }

    func testEmptyUpdatePreservesWorkspace() throws {
        let result = try apply([], to: [draft()])
        XCTAssertEqual(result.expenses.first?.id, "coffee")
        XCTAssertTrue(result.changedExpenseIDs.isEmpty)
    }

    func testSpeechSegmentsJoinInTimeOrderAndDuplicateFinalIsIgnored() {
        var buffer = AppleSpeechTurnBuffer()
        buffer.appendFinal(text: "and tea for three euros", start: 2, end: 4)
        buffer.appendFinal(text: "Coffee for four fifty", start: 0, end: 2)
        buffer.appendFinal(text: "Coffee for four fifty", start: 0, end: 2)
        XCTAssertEqual(buffer.takeUtterance(), "Coffee for four fifty and tea for three euros")
        buffer.appendFinal(text: "and tea for three euros", start: 2, end: 4)
        XCTAssertEqual(buffer.takeUtterance(), "")
        buffer.appendFinal(text: "Coffee for four fifty", start: 5, end: 7)
        XCTAssertEqual(buffer.takeUtterance(), "Coffee for four fifty")
    }

    func testRecognitionAndOverlappingResponsesKeepSaveBlocked() {
        let vm = VoiceModeViewModel()
        vm.open()
        vm.drafts = [draft()]
        vm.handleVoiceEvent(.microphoneStarted)
        vm.handleVoiceEvent(.recognitionPending(true))
        XCTAssertFalse(vm.canEndSession)
        vm.handleVoiceEvent(.responseStarted(id: "first", isAppGenerated: false))
        vm.handleVoiceEvent(.recognitionPending(false))
        vm.handleVoiceEvent(.recognitionPending(true))
        vm.handleVoiceEvent(.responseFinished(id: "first"))
        XCTAssertTrue(vm.isProcessingRequest)
        vm.handleVoiceEvent(.speechActivity(true))
        vm.handleVoiceEvent(.recognitionPending(false))
        XCTAssertFalse(vm.canEndSession)
        vm.handleVoiceEvent(.speechActivity(false))
        XCTAssertTrue(vm.canEndSession)
        vm.cancelSession()
        XCTAssertFalse(vm.isProcessingRequest)
    }

    func testAppleFailurePreservesExistingDraftsForExplicitSave() {
        let vm = VoiceModeViewModel()
        var settings = VoiceSettings.default
        settings.provider = .apple
        settings.appleEnabled = true
        vm.open(settings: settings)
        vm.drafts = [draft()]
        vm.handleVoiceEvent(.recognitionPending(true))
        vm.handleVoiceEvent(.error("Unavailable"))
        XCTAssertEqual(vm.provider, .apple)
        XCTAssertEqual(vm.drafts.count, 1)
        XCTAssertTrue(vm.canSaveDrafts)
        XCTAssertTrue(vm.canEndSession)
        XCTAssertFalse(vm.isProcessingRequest)
    }

    func testQueuedCorrectionSeesPriorAdditionAndKeepsOrder() async throws {
        let finished = expectation(description: "Both requests applied")
        finished.expectedFulfillmentCount = 2
        var payloads: [VoiceWorkspaceSyncPayload] = []
        let queue = AppleVoiceRequestQueue(interpret: { text, drafts in
            if text == "add" {
                try await Task.sleep(for: .milliseconds(20))
                XCTAssertTrue(drafts.isEmpty)
                return AppleWorkspaceUpdate(understanding: text, clarification: "", mutations: [
                    .init(action: .add, title: "Coffee", amount: 4.5)])
            }
            let previous = try XCTUnwrap(drafts.first)
            return AppleWorkspaceUpdate(understanding: text, clarification: "", mutations: [
                .init(action: .update, targetID: previous.id, amount: 5)])
        }, onEvent: { event in
            if case .workspaceSync(let payload) = event {
                payloads.append(payload)
                finished.fulfill()
            }
        }, onFailure: { error in XCTFail(error.localizedDescription) })
        try queue.enqueue("add")
        try queue.enqueue("correct")
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads.first?.expenses.first?.id, payloads.last?.expenses.first?.id)
        XCTAssertEqual(payloads.last?.expenses.first?.amount, 5)
        XCTAssertNotEqual(payloads.first?.responseID, payloads.last?.responseID)
        queue.cancel()
    }

    func testCancelledGenerationCannotEmitLateWorkspace() async throws {
        let started = expectation(description: "Interpretation started")
        let completed = expectation(description: "Cancelled interpretation returned")
        var release: CheckedContinuation<Void, Never>?
        var outputs = 0
        let queue = AppleVoiceRequestQueue(interpret: { _, _ in
            await withCheckedContinuation { continuation in
                release = continuation
                started.fulfill()
            }
            completed.fulfill()
            return AppleWorkspaceUpdate(understanding: "Late", clarification: "", mutations: [
                .init(action: .add, title: "Coffee", amount: 4.5)])
        }, onEvent: { event in
            if case .workspaceSync = event { outputs += 1 }
        }, onFailure: { _ in XCTFail("Cancellation must not report a provider error") })
        try queue.enqueue("add")
        await fulfillment(of: [started], timeout: 3)
        queue.cancel()
        release?.resume()
        await fulfillment(of: [completed], timeout: 3)
        await Task.yield()
        XCTAssertEqual(outputs, 0)
    }

    func testManualRemovalDuringGenerationCannotBeResurrected() async throws {
        let started = expectation(description: "Interpretation started")
        let applied = expectation(description: "Applied after removal")
        var release: CheckedContinuation<Void, Never>?
        var remaining: [VoiceExpenseDraftPayload] = []
        let queue = AppleVoiceRequestQueue(interpret: { _, drafts in
            XCTAssertEqual(drafts.first?.id, "coffee")
            await withCheckedContinuation { continuation in release = continuation; started.fulfill() }
            return AppleWorkspaceUpdate(understanding: "Correction", clarification: "", mutations: [
                .init(action: .update, targetID: "coffee", amount: 6)])
        }, onEvent: { event in
            if case .workspaceSync(let payload) = event { remaining = payload.expenses; applied.fulfill() }
        }, onFailure: { error in XCTFail(error.localizedDescription) })
        queue.updateDrafts([draft()])
        try queue.enqueue("correct")
        await fulfillment(of: [started], timeout: 3)
        queue.updateDrafts([])
        release?.resume()
        await fulfillment(of: [applied], timeout: 3)
        XCTAssertTrue(remaining.isEmpty)
        queue.cancel()
    }

    func testLiveAppleEnglishAddCorrectAndRemoveWhenModelAvailable() async throws {
        try requireDeviceInference()
        guard #available(iOS 26, *), SystemLanguageModel.default.isAvailable else {
            throw XCTSkip("Actual Apple model is unavailable on this test device; live inference still requires validation.")
        }
        let interpreter = AppleWorkspaceInterpreter(usePrivateCloudCompute: false)
        let locale = Locale(identifier: "en_US")
        let added = try await interpreter.interpret(
            "Coffee for four euros fifty today and flowers for twelve euros yesterday.",
            drafts: [], locale: locale, todayISO: today)
        let first = try AppleWorkspaceReducer.apply(added, to: [], todayISO: today, responseID: "live-add")
        XCTAssertEqual(first.expenses.count, 2)
        XCTAssertEqual(first.expenses.compactMap(\.amount).sorted(), [4.5, 12])
        let coffee = try XCTUnwrap(first.expenses.first { $0.amount == 4.5 })
        let flowers = try XCTUnwrap(first.expenses.first { $0.amount == 12 })
        XCTAssertEqual(coffee.dateISO, today)
        XCTAssertEqual(flowers.dateISO, "2026-09-14")
        let corrected = try await interpreter.interpret("The coffee was actually five euros. Everything else stays the same.",
            drafts: first.expenses.map(\.draft), locale: locale, todayISO: today)
        let second = try AppleWorkspaceReducer.apply(corrected, to: first.expenses.map(\.draft), todayISO: today, responseID: "live-correct")
        XCTAssertEqual(second.expenses.first { $0.id == coffee.id }?.amount, 5)
        XCTAssertEqual(second.expenses.first { $0.id == flowers.id }?.amount, 12)
        let removed = try await interpreter.interpret("Remove the flowers.", drafts: second.expenses.map(\.draft), locale: locale, todayISO: today)
        let third = try AppleWorkspaceReducer.apply(removed, to: second.expenses.map(\.draft), todayISO: today, responseID: "live-remove")
        XCTAssertEqual(third.expenses.map(\.id), [coffee.id])
    }

    func testLiveAppleGermanAmountDateAndShareWhenModelAvailable() async throws {
        try requireDeviceInference()
        guard #available(iOS 26, *), SystemLanguageModel.default.isAvailable else {
            throw XCTSkip("Actual Apple model is unavailable on this test device; live inference still requires validation.")
        }
        let interpreter = AppleWorkspaceInterpreter(usePrivateCloudCompute: false)
        let update = try await interpreter.interpret(
            "Für den Einkauf habe ich gestern dreiundzwanzig Euro fünfzig bezahlt. Mein Partner übernimmt vierzig Prozent.",
            drafts: [], locale: Locale(identifier: "de_DE"), todayISO: today)
        let result = try AppleWorkspaceReducer.apply(update, to: [], todayISO: today, responseID: "live-german")
        XCTAssertEqual(result.expenses.count, 1)
        let expense = try XCTUnwrap(result.expenses.first)
        XCTAssertEqual(expense.amount, 23.5)
        XCTAssertEqual(expense.dateISO, "2026-09-14")
        XCTAssertEqual(expense.splitMode, "percent")
        XCTAssertEqual(expense.splitValue, 40)
    }

    func testOldOpenAIEventsCannotAffectAppleSession() {
        let vm = VoiceModeViewModel()
        var settings = VoiceSettings.default
        settings.provider = .apple
        vm.open(settings: settings)
        vm.realtimeVoiceService(RealtimeVoiceService(), didReceive: .error("Old provider disconnected"))
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.errorMessage.isEmpty)
    }

    private func requireDeviceInference() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This simulator rejects Apple inference as unsupported. Run live tests on a supported Apple Intelligence device.")
        #endif
    }

    func testSimulatorCannotAdvertiseAppleVoiceAsReady() async {
        #if targetEnvironment(simulator)
        let availability = await AppleVoiceAvailability.check(locale: Locale(identifier: "en_US"))
        XCTAssertFalse(availability.canStart)
        XCTAssertEqual(availability.messageKey, "AppleSimulatorUnavailable")
        #endif
    }

    func testPCCRemainsGatedWithoutManagedEntitlement() {
        XCTAssertFalse(AppleVoiceAvailability.privateCloudComputeEnabledInBuild)
    }
}
