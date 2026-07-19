import XCTest
@testable import Maeuse

@MainActor
final class RealtimeVoiceWorkspaceTests: XCTestCase {
    private var originalLanguagePreference: AppLanguage = .system

    @MainActor
    override func setUp() {
        super.setUp()
        originalLanguagePreference = LanguageManager.shared.languagePreference
        LanguageManager.shared.languagePreference = .english
    }

    @MainActor
    override func tearDown() {
        LanguageManager.shared.languagePreference = originalLanguagePreference
        super.tearDown()
    }

    func testClientSecretSessionConfigUsesRealtime2AndConstrainedWorkspaceTool() throws {
        let data = try RealtimeSessionConfiguration.requestBodyData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try XCTUnwrap(object["session"] as? [String: Any])

        XCTAssertEqual(session["model"] as? String, "gpt-realtime-2")
        XCTAssertEqual(session["output_modalities"] as? [String], ["text"])

        let reasoning = try XCTUnwrap(session["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "low")

        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "audio/pcm")
        XCTAssertEqual(format["rate"] as? Int, 24000)
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-realtime-whisper")
        let turnDetection = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(turnDetection["type"] as? String, "semantic_vad")

        let tools = try XCTUnwrap(session["tools"] as? [[String: Any]])
        let syncTool = try XCTUnwrap(tools.first)
        XCTAssertEqual(syncTool["name"] as? String, "sync_expense_workspace")
        XCTAssertNil(syncTool["strict"])

        let parameters = try XCTUnwrap(syncTool["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["additionalProperties"] as? Bool, false)
    }

    func testWebSocketSessionConfigUsesWebSocketAudioFields() throws {
        let session = RealtimeSessionConfiguration.webSocketSession()

        XCTAssertEqual(session["output_modalities"] as? [String], ["text"])
        XCTAssertNil(session["modalities"])
        XCTAssertNil(session["input_audio_format"])
        XCTAssertNil(session["turn_detection"])

        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "audio/pcm")
        XCTAssertEqual(format["rate"] as? Int, 24000)
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-realtime-whisper")
        let turnDetection = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(turnDetection["type"] as? String, "semantic_vad")

        let tools = try XCTUnwrap(session["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["name"] as? String, "sync_expense_workspace")
    }

    func testParsesWorkspaceSyncFromResponseDone() throws {
        let arguments = """
        {
          "user_understanding": "I bought coffee for 4 euros.",
          "assistant_confirmation": "Added coffee for 4.00 euros.",
          "expenses": [
            {
              "id": "expense-1",
              "title": "Coffee",
              "amount": 4,
              "date_iso": "2026-05-14",
              "split_mode": "percent",
              "split_value": 50,
              "confidence": 0.9,
              "missing_fields": []
            }
          ],
          "changed_expense_ids": ["expense-1"],
          "removed_expense_ids": []
        }
        """

        let event: [String: Any] = [
            "type": "response.done",
            "response": [
                "output": [
                    [
                        "type": "function_call",
                        "name": "sync_expense_workspace",
                        "call_id": "call-1",
                        "arguments": arguments
                    ]
                ]
            ]
        ]

        var parser = RealtimeServerEventParser()
        let data = try JSONSerialization.data(withJSONObject: event)
        let parsed = try parser.parse(data)

        guard case let .workspaceSync(payload, callID) = parsed.first else {
            return XCTFail("Expected workspace sync event.")
        }

        XCTAssertEqual(callID, "call-1")
        XCTAssertEqual(payload.userUnderstanding, "I bought coffee for 4 euros.")
        XCTAssertEqual(payload.expenses.first?.draft.normalizedTitle, "Coffee")
        XCTAssertEqual(payload.expenses.first?.draft.normalizedAmount, 4)
    }

    func testParsesFunctionArgumentsDoneOnlyOnce() throws {
        let arguments = """
        {
          "user_understanding": "Remove the coffee.",
          "assistant_confirmation": "Removed coffee.",
          "expenses": [],
          "changed_expense_ids": [],
          "removed_expense_ids": ["expense-1"]
        }
        """

        let doneEvent: [String: Any] = [
            "type": "response.function_call_arguments.done",
            "name": "sync_expense_workspace",
            "call_id": "call-1",
            "arguments": arguments
        ]
        let responseDoneEvent: [String: Any] = [
            "type": "response.done",
            "response": [
                "output": [
                    [
                        "type": "function_call",
                        "name": "sync_expense_workspace",
                        "call_id": "call-1",
                        "arguments": arguments
                    ]
                ]
            ]
        ]

        var parser = RealtimeServerEventParser()
        let first = try parser.parse(try JSONSerialization.data(withJSONObject: doneEvent))
        let second = try parser.parse(try JSONSerialization.data(withJSONObject: responseDoneEvent))

        XCTAssertEqual(first.compactMap(\.workspaceSyncPayload).count, 1)
        XCTAssertEqual(second.compactMap(\.workspaceSyncPayload).count, 0)
    }

    func testParsesInputAudioTranscriptionDeltaAndCompletedEvents() throws {
        var parser = RealtimeServerEventParser()
        let deltaEvent: [String: Any] = [
            "type": "conversation.item.input_audio_transcription.delta",
            "item_id": "item-1",
            "content_index": 0,
            "delta": "Coffee "
        ]
        let completedEvent: [String: Any] = [
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": "item-1",
            "content_index": 0,
            "transcript": "Coffee for 5 euros."
        ]

        let delta = try parser.parse(try JSONSerialization.data(withJSONObject: deltaEvent))
        let completed = try parser.parse(try JSONSerialization.data(withJSONObject: completedEvent))

        XCTAssertEqual(delta, [.userTranscriptDelta(itemID: "item-1", text: "Coffee ")])
        XCTAssertEqual(completed, [.userTranscriptDone(itemID: "item-1", text: "Coffee for 5 euros.")])
    }

    func testWorkspaceAppliesDateAndSplitDefaultsWithoutMissingBadges() {
        let viewModel = VoiceModeViewModel()
        let payload = VoiceWorkspaceSyncPayload(
            userUnderstanding: "I bought groceries for 10 euros.",
            assistantConfirmation: "Added groceries for 10.00 euros.",
            expenses: [
                VoiceExpenseDraftPayload(
                    id: "expense-1",
                    title: "Groceries",
                    amount: 10,
                    dateISO: nil,
                    splitMode: nil,
                    splitValue: nil,
                    confidence: 0.92,
                    missingFields: [.date, .split]
                )
            ],
            changedExpenseIDs: ["expense-1"],
            removedExpenseIDs: []
        )

        viewModel.realtimeVoiceService(RealtimeVoiceService(), didReceive: .workspaceSync(payload))

        let draft = viewModel.drafts.first
        XCTAssertEqual(draft?.dateISO, VoiceModeViewModel.todayISOString())
        XCTAssertEqual(draft?.splitMode, .percent)
        XCTAssertEqual(draft?.splitValue, 50)
        XCTAssertEqual(draft?.missingFields, [])
        XCTAssertEqual(viewModel.takeawayText, "1 expense · €10.00 total · €5.00 partner")
    }

    func testWorkspaceSyncDoesNotUseModelParaphraseAsUserChat() {
        let viewModel = VoiceModeViewModel()
        let payload = VoiceWorkspaceSyncPayload(
            userUnderstanding: "I bought coffee for 5 euros.",
            assistantConfirmation: "Added coffee for 5.00 euros.",
            expenses: [
                VoiceExpenseDraftPayload(
                    id: "expense-1",
                    title: "Coffee",
                    amount: 5,
                    dateISO: "2026-05-14",
                    splitMode: "percent",
                    splitValue: 50,
                    confidence: 0.92,
                    missingFields: []
                )
            ],
            changedExpenseIDs: ["expense-1"],
            removedExpenseIDs: []
        )

        viewModel.realtimeVoiceService(RealtimeVoiceService(), didReceive: .workspaceSync(payload))

        XCTAssertEqual(viewModel.conversation.map(\.role), [.assistant])
        XCTAssertEqual(viewModel.conversation.first?.text, "Added coffee for 5.00 euros.")
    }

    func testInputTranscriptionDrivesLiveAndFinalUserChat() {
        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()

        viewModel.realtimeVoiceService(service, didReceive: .userTranscriptDelta(itemID: "item-1", text: "Coffee "))
        viewModel.realtimeVoiceService(service, didReceive: .userTranscriptDelta(itemID: "item-1", text: "for 5"))

        XCTAssertEqual(viewModel.liveUserTranscript, "Coffee for 5")
        XCTAssertEqual(viewModel.conversation, [])

        viewModel.realtimeVoiceService(service, didReceive: .userTranscriptDone(itemID: "item-1", text: "Coffee for 5 euros."))

        XCTAssertEqual(viewModel.liveUserTranscript, "")
        XCTAssertEqual(viewModel.conversation.map(\.role), [.user])
        XCTAssertEqual(viewModel.conversation.first?.text, "Coffee for 5 euros.")
    }

    func testStatusEventsDoNotAddSessionBubbles() {
        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()

        viewModel.realtimeVoiceService(service, didReceive: .microphoneReady)
        viewModel.realtimeVoiceService(service, didReceive: .microphoneStarted)
        viewModel.realtimeVoiceService(service, didReceive: .microphoneLevel(0.4))
        viewModel.realtimeVoiceService(service, didReceive: .listeningStarted)

        XCTAssertEqual(viewModel.conversation, [])
        XCTAssertTrue(viewModel.microphoneIsActive)
        XCTAssertEqual(viewModel.microphoneLevel, 0.4)
        XCTAssertEqual(viewModel.phase, .listening)
        XCTAssertEqual(viewModel.stateLabel, "Listening...")
    }

    func testRejectsIncompleteDraftsForSaving() {
        let viewModel = VoiceModeViewModel()
        viewModel.drafts = [
            VoiceExpenseDraft(
                id: "missing-title",
                title: "",
                amount: 12.345,
                dateISO: "2026-05-14",
                splitMode: nil,
                splitValue: nil,
                confidence: 0.5,
                missingFields: [.title, .split]
            ),
            VoiceExpenseDraft(
                id: "missing-amount",
                title: "Bakery",
                amount: nil,
                dateISO: "2026-05-14",
                splitMode: .fixed,
                splitValue: 2,
                confidence: 0.4,
                missingFields: [.amount]
            )
        ]

        let expenses = viewModel.expensesForSaving()

        XCTAssertFalse(viewModel.canSaveDrafts)
        XCTAssertTrue(expenses.isEmpty)
    }

    func testValidatesAndBoundsVoiceDraftsBeforeSaving() {
        let viewModel = VoiceModeViewModel()
        let draft = VoiceExpenseDraft(
            id: "expense-1",
            title: "Dinner",
            amount: 20,
            dateISO: "2026-05-14",
            splitMode: .fixed,
            splitValue: 25,
            confidence: 0.9,
            missingFields: []
        )
        viewModel.drafts = [draft]

        XCTAssertTrue(viewModel.canSaveDrafts)
        XCTAssertEqual(draft.normalizedSplitValue, 20)
        XCTAssertEqual(viewModel.expensesForSaving().first?.splitValue, 20)

        viewModel.drafts[0].splitMode = .percent
        viewModel.drafts[0].splitValue = 125

        XCTAssertFalse(viewModel.canSaveDrafts)
        XCTAssertEqual(viewModel.drafts[0].normalizedSplitValue, 100)
        XCTAssertTrue(viewModel.expensesForSaving().isEmpty)
    }

    func testExpenseAmountFormattingUsesSelectedAppLanguage() {
        LanguageManager.shared.languagePreference = .german
        let viewModel = ExpenseEditorViewModel()
        let expense = Expense(amount: 12.34, desc: "Lunch", date: Date())

        viewModel.prepareForEdit(expense)

        XCTAssertEqual(viewModel.amountText, "12,34")
    }

    func testBackupExportRoundTripsThroughImporter() throws {
        let date = try XCTUnwrap(Expense.dateFromISO("2026-07-11"))
        let expense = Expense(id: "expense-backup", amount: 42.75, desc: "Groceries",
                              date: date, splitMode: .percent, splitValue: 35)

        let data = try BackupService.exportBackup(expenses: [expense])
        let imported = try BackupService.parseBackup(data: data)

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].id, "expense-backup")
        XCTAssertEqual(imported[0].amount, 42.75)
        XCTAssertEqual(imported[0].description, "Groceries")
        XCTAssertEqual(imported[0].date, "2026-07-11")
        XCTAssertEqual(imported[0].splitMode, "percent")
        XCTAssertEqual(imported[0].splitValue, 35)
    }

    func testVoiceSettingsRequireCurrentConsentForReadiness() {
        var settings = VoiceSettings(
            apiKeySuffix: "7mQ2",
            verifiedAt: Date(),
            enabled: true,
            consentVersion: nil,
            consentedAt: nil
        )

        XCTAssertTrue(settings.isVerified)
        XCTAssertFalse(settings.hasCurrentConsent)
        XCTAssertFalse(settings.isReady)

        settings.consentVersion = VoiceSettings.currentConsentVersion
        settings.consentedAt = Date()

        XCTAssertTrue(settings.hasCurrentConsent)
        XCTAssertTrue(settings.isReady)
    }

    func testLegacyVoiceSettingsDecodeWithoutConsent() throws {
        let legacy = """
        {
          "apiKeySuffix": "7mQ2",
          "verifiedAt": 796348800,
          "enabled": true
        }
        """

        let settings = try JSONDecoder().decode(VoiceSettings.self, from: Data(legacy.utf8))

        XCTAssertTrue(settings.enabled)
        XCTAssertTrue(settings.hapticsEnabled)
        XCTAssertFalse(settings.hasCurrentConsent)
        XCTAssertFalse(settings.isReady)
    }

    func testVoiceSettingsDecodeHapticsDisabled() throws {
        let json = """
        {
          "apiKeySuffix": "7mQ2",
          "verifiedAt": 796348800,
          "enabled": true,
          "hapticsEnabled": false,
          "consentVersion": 1,
          "consentedAt": 796348800
        }
        """

        let settings = try JSONDecoder().decode(VoiceSettings.self, from: Data(json.utf8))

        XCTAssertFalse(settings.hapticsEnabled)
        XCTAssertTrue(settings.enabled)
    }
}

private extension RealtimeParsedEvent {
    var workspaceSyncPayload: VoiceWorkspaceSyncPayload? {
        if case let .workspaceSync(payload, _) = self {
            return payload
        }
        return nil
    }
}
