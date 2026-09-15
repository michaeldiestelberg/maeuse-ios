import XCTest
@testable import Maeuse

@MainActor
final class RealtimeVoiceWorkspaceTests: XCTestCase {
    private var originalLanguagePreference: AppLanguage = .system

    // The async overrides carry the class's `@MainActor` isolation; the synchronous
    // `setUp()`/`tearDown()` are nonisolated in XCTestCase, which is an error under
    // the Swift 6 language mode.
    override func setUp() async throws {
        try await super.setUp()
        originalLanguagePreference = LanguageManager.shared.languagePreference
        LanguageManager.shared.languagePreference = .english
    }

    override func tearDown() async throws {
        LanguageManager.shared.languagePreference = originalLanguagePreference
        try await super.tearDown()
    }

    func testClientSecretSessionConfigUsesRealtime21WithoutTranscription() throws {
        let data = try RealtimeSessionConfiguration.requestBodyData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try XCTUnwrap(object["session"] as? [String: Any])

        XCTAssertEqual(session["model"] as? String, "gpt-realtime-2.1")
        XCTAssertEqual(session["output_modalities"] as? [String], ["text"])

        let reasoning = try XCTUnwrap(session["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "low")

        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "audio/pcm")
        XCTAssertEqual(format["rate"] as? Int, 24000)
        XCTAssertNil(input["transcription"])
        let turnDetection = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(turnDetection["type"] as? String, "semantic_vad")

        let tools = try XCTUnwrap(session["tools"] as? [[String: Any]])
        let syncTool = try XCTUnwrap(tools.first)
        XCTAssertEqual(syncTool["name"] as? String, "sync_expense_workspace")
        XCTAssertNil(syncTool["strict"])
        XCTAssertEqual(session["tool_choice"] as? String, "required")

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
        XCTAssertNil(input["transcription"])
        let turnDetection = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(turnDetection["type"] as? String, "semantic_vad")

        let tools = try XCTUnwrap(session["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["name"] as? String, "sync_expense_workspace")
    }

    func testParsesWorkspaceSyncFromResponseDone() throws {
        let arguments = """
        {
          "user_understanding": "I bought coffee for 4 euros.",
          "clarification_question": "",
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
          "clarification_question": "",
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
        let duplicate = try parser.parse(try JSONSerialization.data(withJSONObject: doneEvent))
        XCTAssertTrue(duplicate.isEmpty)
        let second = try parser.parse(try JSONSerialization.data(withJSONObject: responseDoneEvent))

        XCTAssertEqual(first.compactMap(\.workspaceSyncPayload).count, 1)
        XCTAssertEqual(second.compactMap(\.workspaceSyncPayload).count, 0)
    }

    func testWorkspaceAppliesDateAndSplitDefaultsWithoutMissingBadges() {
        let viewModel = VoiceModeViewModel()
        let payload = VoiceWorkspaceSyncPayload(
            userUnderstanding: "I bought groceries for 10 euros.",
            clarificationQuestion: "",
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

    func testWorkspaceSyncReplacesLatestUnderstandingAndAppliesCorrections() {
        let viewModel = VoiceModeViewModel()
        let payload = VoiceWorkspaceSyncPayload(
            userUnderstanding: "I bought coffee for 5 euros.",
            clarificationQuestion: "",
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

        XCTAssertEqual(viewModel.understandingHistory.last?.text, "I bought coffee for 5 euros.")
        XCTAssertTrue(viewModel.clarificationQuestion.isEmpty)
        XCTAssertEqual(viewModel.drafts.first?.amount, 5)

        let correction = VoiceWorkspaceSyncPayload(
            userUnderstanding: "The coffee was 6 euros.",
            clarificationQuestion: "",
            expenses: [
                VoiceExpenseDraftPayload(
                    id: "expense-1", title: "Coffee", amount: 6,
                    dateISO: "2026-05-14", splitMode: "percent", splitValue: 50,
                    confidence: 0.92, missingFields: []
                )
            ],
            changedExpenseIDs: ["expense-1"], removedExpenseIDs: []
        )
        viewModel.realtimeVoiceService(RealtimeVoiceService(), didReceive: .workspaceSync(correction))

        XCTAssertEqual(viewModel.understandingHistory.map(\.text), ["I bought coffee for 5 euros.", "The coffee was 6 euros."])
        XCTAssertEqual(viewModel.drafts.count, 1)
        XCTAssertEqual(viewModel.drafts.first?.id, "expense-1")
        XCTAssertEqual(viewModel.drafts.first?.amount, 6)
    }

    func testUnclearAudioShowsClarificationWithoutInventingUnderstanding() {
        let viewModel = VoiceModeViewModel()
        let payload = VoiceWorkspaceSyncPayload(
            userUnderstanding: " \n ",
            clarificationQuestion: "How much was the coffee?",
            expenses: [], changedExpenseIDs: [], removedExpenseIDs: []
        )
        viewModel.realtimeVoiceService(RealtimeVoiceService(), didReceive: .workspaceSync(payload))

        XCTAssertTrue(viewModel.understandingHistory.isEmpty)
        XCTAssertEqual(viewModel.clarificationQuestion, "How much was the coffee?")
        XCTAssertTrue(viewModel.drafts.isEmpty)
    }

    func testUnderstandingLabelUsesSelectedAppLanguage() {
        XCTAssertEqual(loc("VoiceWhatUnderstood"), "What I understood")
        LanguageManager.shared.languagePreference = .german
        XCTAssertEqual(loc("VoiceWhatUnderstood"), "So habe ich dich verstanden")
    }

    func testResetClearsUnderstandingAndClarification() {
        let viewModel = VoiceModeViewModel()
        viewModel.realtimeVoiceService(RealtimeVoiceService(), didReceive: .workspaceSync(
            VoiceWorkspaceSyncPayload(
                userUnderstanding: "Coffee", clarificationQuestion: "How much was it?",
                expenses: [], changedExpenseIDs: [], removedExpenseIDs: []
            )
        ))
        viewModel.realtimeVoiceService(RealtimeVoiceService(), didReceive: .assistantTextDelta("How"))

        viewModel.resetWorkspace()

        XCTAssertTrue(viewModel.understandingHistory.isEmpty)
        XCTAssertTrue(viewModel.clarificationQuestion.isEmpty)
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testProcessingPersistsDuringSpeechAndUntilEachPendingResultArrives() {
        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()
        func send(_ event: RealtimeVoiceServiceEvent) { viewModel.realtimeVoiceService(service, didReceive: event) }
        func sync(_ responseID: String, amount: Double) {
            send(.workspaceSync(VoiceWorkspaceSyncPayload(responseID: responseID,
                userUnderstanding: "Flowers", clarificationQuestion: "",
                expenses: [VoiceExpenseDraftPayload(id: "flowers", title: "Flowers", amount: amount,
                    dateISO: nil, splitMode: nil, splitValue: nil, confidence: 1, missingFields: [])],
                changedExpenseIDs: ["flowers"], removedExpenseIDs: [])))
        }
        send(.microphoneStarted)
        send(.listeningStarted)
        XCTAssertFalse(viewModel.isProcessingRequest)
        XCTAssertTrue(viewModel.isUserSpeaking)
        send(.listeningStopped)
        XCTAssertTrue(viewModel.isProcessingRequest, "Show processing before response.created arrives")
        XCTAssertTrue(viewModel.drafts.isEmpty, "Never invent a placeholder expense")
        send(.responseStarted(id: "first", isAppGenerated: false))
        send(.listeningStarted)
        send(.microphoneLevel(0.7))
        XCTAssertTrue(viewModel.isProcessingRequest, "Speaking must not hide pending work")
        XCTAssertTrue(viewModel.isUserSpeaking)
        XCTAssertEqual(viewModel.microphoneLevel, 0.7)
        send(.listeningStopped)
        sync("first", amount: 12)
        send(.responseFinished(id: "first"))
        XCTAssertTrue(viewModel.isProcessingRequest, "Earlier completion must not clear a later spoken request")
        XCTAssertFalse(viewModel.canEndSession)
        send(.responseStarted(id: "second", isAppGenerated: false))
        sync("second", amount: 13.5)
        XCTAssertFalse(viewModel.isProcessingRequest, "Stop as soon as the structured result is visible")
        XCTAssertEqual(viewModel.changedFieldsByExpenseID["flowers"], [.amount])
        send(.responseFinished(id: "second"))
        XCTAssertTrue(viewModel.canEndSession)
        XCTAssertTrue(viewModel.microphoneIsReady)
    }

    func testProcessingClearsOnNoOpCompletionErrorAndReset() {
        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()
        func send(_ event: RealtimeVoiceServiceEvent) { viewModel.realtimeVoiceService(service, didReceive: event) }
        send(.microphoneStarted)
        send(.listeningStopped)
        send(.responseStarted(id: "clarification", isAppGenerated: false))
        send(.responseFinished(id: "clarification"))
        XCTAssertFalse(viewModel.isProcessingRequest)
        send(.listeningStopped)
        send(.responseStarted(id: "note", isAppGenerated: true))
        send(.responseFinished(id: "note"))
        XCTAssertTrue(viewModel.isProcessingRequest, "An app note cannot consume pending speech")
        send(.error("Disconnected"))
        XCTAssertFalse(viewModel.isProcessingRequest)
        XCTAssertFalse(viewModel.isUserSpeaking)
        viewModel.resetWorkspace()
        XCTAssertFalse(viewModel.isProcessingRequest)
        XCTAssertTrue(viewModel.changedFieldsByExpenseID.isEmpty)
    }

    func testResponseLifecycleIncludesIdentityAndSource() throws {
        var parser = RealtimeServerEventParser()
        let created: [String: Any] = ["type": "response.created", "response": [
            "id": "note", "metadata": ["maeuse_source": "workspace_note"]]]
        XCTAssertEqual(try parser.parse(JSONSerialization.data(withJSONObject: created)),
            [.responseStarted(id: "note", isAppGenerated: true)])
        let done: [String: Any] = ["type": "response.done", "response": ["id": "note", "output": []]]
        XCTAssertEqual(try parser.parse(JSONSerialization.data(withJSONObject: done)), [.responseFinished(id: "note")])
    }

    func testMouseReadinessWaitsForCaptureRatherThanConnectionOrPermission() {
        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()
        viewModel.phase = .connecting

        viewModel.realtimeVoiceService(service, didReceive: .connected)
        viewModel.realtimeVoiceService(service, didReceive: .microphoneReady)
        XCTAssertFalse(viewModel.microphoneIsReady)
        XCTAssertEqual(viewModel.phase, .connecting)

        viewModel.realtimeVoiceService(service, didReceive: .microphoneStarted)
        XCTAssertTrue(viewModel.microphoneIsReady)
        XCTAssertEqual(viewModel.phase, .listening)

        viewModel.realtimeVoiceService(service, didReceive: .responseStarted(id: "unidentified-response", isAppGenerated: false))
        XCTAssertTrue(viewModel.microphoneIsReady, "Processing does not restart the connection animation")
        viewModel.realtimeVoiceService(service, didReceive: .microphoneStopped)
        XCTAssertFalse(viewModel.microphoneIsReady)
    }

    func testFailureAndSessionEndNeverShowAReadyMicrophone() {
        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()
        viewModel.realtimeVoiceService(service, didReceive: .microphoneStarted)
        viewModel.realtimeVoiceService(service, didReceive: .error("Connection failed"))
        XCTAssertFalse(viewModel.microphoneIsReady)
        XCTAssertEqual(viewModel.errorMessage, "Connection failed")

        viewModel.resetWorkspace()
        XCTAssertFalse(viewModel.microphoneIsReady)
        viewModel.realtimeVoiceService(service, didReceive: .microphoneStarted)
        viewModel.phase = .finalizing
        XCTAssertFalse(viewModel.microphoneIsReady)
        viewModel.realtimeVoiceService(service, didReceive: .disconnected)
        XCTAssertFalse(viewModel.microphoneIsReady)
        XCTAssertEqual(viewModel.phase, .finalizing)
    }

    func testClosingWhileConnectionStartsKeepsTheSessionClosed() async throws {
        let viewModel = VoiceModeViewModel()
        viewModel.open()
        viewModel.startSession()
        viewModel.cancelSession()
        // Let the cancelled connection task run; it must neither connect nor
        // publish a delayed connection error into the cleared workspace.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(viewModel.isPresented)
        XCTAssertFalse(viewModel.microphoneIsReady)
        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertTrue(viewModel.errorMessage.isEmpty)
    }

    func testStatusEventsDoNotAddSessionBubbles() {
        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()

        viewModel.realtimeVoiceService(service, didReceive: .microphoneReady)
        viewModel.realtimeVoiceService(service, didReceive: .microphoneStarted)
        viewModel.realtimeVoiceService(service, didReceive: .microphoneLevel(0.4))
        viewModel.realtimeVoiceService(service, didReceive: .listeningStarted)

        XCTAssertTrue(viewModel.understandingHistory.isEmpty)
        XCTAssertTrue(viewModel.microphoneIsActive)
        XCTAssertEqual(viewModel.microphoneLevel, 0.4)
        XCTAssertEqual(viewModel.phase, .listening)
        XCTAssertEqual(viewModel.stateLabel, "Listening...")
    }

    func testMicrophoneMeterMakesQuietAndNormalSpeechVisible() {
        // Alternating positive/negative PCM samples have exactly the specified RMS.
        func audio(decibels: Double) -> Data {
            let amplitude = Int16((pow(10, decibels / 20) * 32_767).rounded())
            return (0..<1_024).reduce(into: Data()) { data, index in
                var sample = (index.isMultiple(of: 2) ? amplitude : -amplitude).littleEndian
                withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
            }
        }
        let quiet = audio(decibels: -45)
        let normal = audio(decibels: -30)
        XCTAssertEqual(VoiceInputMeter.level(pcm16: audio(decibels: -65)), 0)
        XCTAssertEqual(VoiceInputMeter.level(pcm16: quiet), 0.25, accuracy: 0.01)
        XCTAssertEqual(VoiceInputMeter.level(pcm16: normal), 0.625, accuracy: 0.01)
        XCTAssertEqual(VoiceInputMeter.level(pcm16: audio(decibels: -10)), 1)

        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()
        viewModel.realtimeVoiceService(service, didReceive: .microphoneStarted)
        for data in [quiet, normal, Data(repeating: 0, count: 2_048)] {
            viewModel.realtimeVoiceService(service, didReceive: .microphoneLevel(VoiceInputMeter.level(pcm16: data)))
            XCTAssertEqual(viewModel.microphoneLevel, VoiceInputMeter.level(pcm16: data))
            XCTAssertTrue(viewModel.microphoneIsReady)
        }
        XCTAssertEqual(viewModel.microphoneLevel, 0, "Pauses must return to the idle wave")
    }

    func testMicrophoneMeterHandlesSilenceInvalidDataAndSignedClipping() {
        XCTAssertEqual(VoiceInputMeter.level(pcm16: Data()), 0)
        XCTAssertEqual(VoiceInputMeter.level(pcm16: Data([0xFF])), 0)
        XCTAssertEqual(VoiceInputMeter.level(pcm16: Data(repeating: 0, count: 100)), 0)
        XCTAssertEqual(VoiceInputMeter.level(pcm16: Data([0x00, 0x80, 0xFF, 0x7F])), 1)
    }

    func testThreeDraftsStayInPlaceWhenCorrectionPayloadReordersThem() {
        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()
        func draft(_ id: String, _ amount: Double, confidence: Double = 1) -> VoiceExpenseDraftPayload {
            VoiceExpenseDraftPayload(id: id, title: id, amount: amount,
                dateISO: "2026-09-12", splitMode: "percent", splitValue: 50,
                confidence: confidence, missingFields: [])
        }
        func sync(_ entries: [VoiceExpenseDraftPayload], understanding: String) {
            viewModel.realtimeVoiceService(service, didReceive: .workspaceSync(
                VoiceWorkspaceSyncPayload(userUnderstanding: understanding, clarificationQuestion: "",
                    expenses: entries, changedExpenseIDs: entries.map(\.id), removedExpenseIDs: [])))
        }
        sync([draft("flowers", 12), draft("coffee", 4.5), draft("film", 3.99)], understanding: "Three expenses")
        let coffeeTimestamp = viewModel.drafts[1].lastChangedAt
        XCTAssertEqual(viewModel.totalAmount, 20.49)
        XCTAssertTrue(viewModel.updatedExpenseIDs.isEmpty)
        // Reproduce narration arriving before and after the structured update.
        viewModel.realtimeVoiceService(service, didReceive: .assistantTextDelta("I'll update that"))
        viewModel.realtimeVoiceService(service, didReceive: .assistantText("I'll update that"))
        XCTAssertEqual(viewModel.understandingHistory.last?.text, "Three expenses")
        sync([draft("film", 3.99), draft("flowers", 13.5), draft("coffee", 4.5, confidence: 0.8)], understanding: "Flowers were 13.50")
        viewModel.realtimeVoiceService(service, didReceive: .assistantText("Updated the flowers"))
        XCTAssertEqual(viewModel.drafts.map(\.id), ["flowers", "coffee", "film"])
        XCTAssertEqual(viewModel.updatedExpenseIDs, ["flowers"])
        XCTAssertEqual(viewModel.drafts[1].lastChangedAt, coffeeTimestamp)
        XCTAssertEqual(viewModel.understandingHistory.last?.text, "Flowers were 13.50")
        XCTAssertTrue(viewModel.clarificationQuestion.isEmpty)
        XCTAssertEqual(viewModel.totalAmount, 21.99)
        XCTAssertEqual(viewModel.expensesForSaving().count, 3)
        viewModel.removeDraft(viewModel.drafts[1])
        XCTAssertEqual(viewModel.drafts.map(\.id), ["flowers", "film"])
        XCTAssertEqual(viewModel.totalAmount, 17.49)
        XCTAssertEqual(viewModel.understandingHistory.map(\.text), ["Three expenses", "Flowers were 13.50"])
    }

    func testClarificationClearsAfterAnswerAndSavingWaitsForResponse() {
        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()
        viewModel.realtimeVoiceService(service, didReceive: .workspaceSync(
            VoiceWorkspaceSyncPayload(userUnderstanding: "Coffee", clarificationQuestion: "How much?",
                expenses: [], changedExpenseIDs: [], removedExpenseIDs: [])))
        viewModel.realtimeVoiceService(service, didReceive: .assistantText("Sure, I'll add it"))
        XCTAssertEqual(viewModel.clarificationQuestion, "How much?")
        viewModel.realtimeVoiceService(service, didReceive: .responseStarted(id: "unidentified-response", isAppGenerated: false))
        XCTAssertFalse(viewModel.canEndSession)
        viewModel.realtimeVoiceService(service, didReceive: .workspaceSync(
            VoiceWorkspaceSyncPayload(userUnderstanding: "Coffee for 4.50", clarificationQuestion: "",
                expenses: [VoiceExpenseDraftPayload(id: "coffee", title: "Coffee", amount: 4.5,
                    dateISO: nil, splitMode: nil, splitValue: nil, confidence: 1, missingFields: [])],
                changedExpenseIDs: ["coffee"], removedExpenseIDs: [])))
        XCTAssertTrue(viewModel.clarificationQuestion.isEmpty)
        XCTAssertTrue(viewModel.canSaveDrafts)
        XCTAssertEqual(viewModel.understandingHistory.last?.text, "Coffee for 4.50")
    }

    func testHistoryDeduplicatesResponseButKeepsRepeatedSpeechAndIgnoresEmptyNotes() {
        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()
        func sync(_ id: String, _ text: String, question: String = "") {
            var payload = VoiceWorkspaceSyncPayload(userUnderstanding: text, clarificationQuestion: question,
                expenses: [], changedExpenseIDs: [], removedExpenseIDs: [])
            payload.responseID = id
            viewModel.realtimeVoiceService(service, didReceive: .workspaceSync(payload))
        }
        sync("request-1", "  Coffee for four euros.  ")
        sync("request-1", "Coffee, four euros, split equally.")
        sync("request-2", "Coffee for four euros.")
        sync("request-3", "Actually, make that five.")
        sync("app-note", "")
        sync("unclear", " \n ", question: "Which expense?")
        XCTAssertEqual(viewModel.understandingHistory.map(\.text), [
            "Coffee for four euros.", "Coffee for four euros.", "Actually, make that five."
        ])
        XCTAssertEqual(viewModel.understandingHistory.map(\.id), ["request-1", "request-2", "request-3"])
        XCTAssertEqual(viewModel.clarificationQuestion, "Which expense?")
        viewModel.cancelSession()
        XCTAssertTrue(viewModel.understandingHistory.isEmpty)
        viewModel.open()
        sync("request-1", "A fresh session.")
        XCTAssertEqual(viewModel.understandingHistory.map(\.text), ["A fresh session."])
        viewModel.finishAfterSave()
        XCTAssertTrue(viewModel.understandingHistory.isEmpty)
    }

    func testHistoryUsesResponseIdentityAcrossToolCallsAndCompletionFallback() throws {
        var parser = RealtimeServerEventParser()
        let viewModel = VoiceModeViewModel()
        let service = RealtimeVoiceService()
        let arguments = #"{"user_understanding":"Actually, fourteen.","clarification_question":"","expenses":[],"changed_expense_ids":[],"removed_expense_ids":[]}"#
        func deliver(_ event: [String: Any]) throws {
            for parsed in try parser.parse(JSONSerialization.data(withJSONObject: event)) {
                if case let .workspaceSync(payload, _) = parsed {
                    viewModel.realtimeVoiceService(service, didReceive: .workspaceSync(payload))
                }
            }
        }
        try deliver(["type": "response.function_call_arguments.done", "response_id": "response-1",
            "call_id": "call-1", "name": "sync_expense_workspace", "arguments": arguments])
        try deliver(["type": "response.function_call_arguments.done", "response_id": "response-1",
            "call_id": "call-2", "name": "sync_expense_workspace", "arguments": arguments])
        try deliver(["type": "response.done", "response": ["id": "response-1", "output": [
            ["type": "function_call", "name": "sync_expense_workspace", "call_id": "call-2", "arguments": arguments]]]])
        XCTAssertEqual(viewModel.understandingHistory.count, 1)
        try deliver(["type": "response.done", "response": ["id": "response-2", "output": [
            ["type": "function_call", "name": "sync_expense_workspace", "call_id": "call-3", "arguments": arguments]]]])
        XCTAssertEqual(viewModel.understandingHistory.map(\.id), ["response-1", "response-2"])
    }

    func testAppGeneratedResponsesNeverAppearAsSpokenHistory() throws {
        let arguments = #"{"user_understanding":"I removed coffee.","clarification_question":"","expenses":[],"changed_expense_ids":[],"removed_expense_ids":["coffee"]}"#
        for useCompletionFallback in [false, true] {
            var parser = RealtimeServerEventParser()
            let response: [String: Any] = ["id": "note-response", "metadata": ["maeuse_source": "workspace_note"],
                "output": [["type": "function_call", "name": "sync_expense_workspace", "call_id": "note-call", "arguments": arguments]]]
            let events: [RealtimeParsedEvent]
            if useCompletionFallback {
                events = try parser.parse(JSONSerialization.data(withJSONObject: ["type": "response.done", "response": response]))
            } else {
                _ = try parser.parse(JSONSerialization.data(withJSONObject: ["type": "response.created", "response": response]))
                events = try parser.parse(JSONSerialization.data(withJSONObject: ["type": "response.function_call_arguments.done",
                    "response_id": "note-response", "call_id": "note-call", "name": "sync_expense_workspace", "arguments": arguments]))
            }
            let payload = try XCTUnwrap(events.compactMap(\.workspaceSyncPayload).first)
            XCTAssertTrue(payload.isAppGenerated)
            let viewModel = VoiceModeViewModel()
            viewModel.drafts = [VoiceExpenseDraft(id: "coffee", title: "Coffee", amount: 4,
                dateISO: nil, splitMode: .percent, splitValue: 50, confidence: 1, missingFields: [])]
            viewModel.realtimeVoiceService(RealtimeVoiceService(), didReceive: .workspaceSync(payload))
            XCTAssertTrue(viewModel.understandingHistory.isEmpty)
            XCTAssertTrue(viewModel.drafts.isEmpty, "App notes must still synchronize the workspace")
        }
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

    // MARK: - Backup import guard clauses
    //
    // `parseBackup` is the gate in front of `replaceAllExpenses`, which deletes every
    // stored expense before inserting. A backup that slips through the gate malformed
    // is unrecoverable data loss, so each rejection path is covered here.

    private func backupJSON(_ entries: String) -> Data {
        Data("[\(entries)]".utf8)
    }

    private func backupEntry(id: String, date: String = "2026-07-11") -> String {
        """
        {"id":"\(id)","amount":10.5,"description":"Coffee","date":"\(date)",
         "splitMode":"percent","splitValue":50,"createdAt":"2026-07-11T09:00:00Z"}
        """
    }

    func testParseBackupRejectsDuplicateExpenseIDs() {
        let data = backupJSON("\(backupEntry(id: "dupe")),\(backupEntry(id: "dupe"))")

        XCTAssertThrowsError(try BackupService.parseBackup(data: data)) { error in
            XCTAssertEqual(error as? BackupService.BackupError, .duplicateExpenseIDs)
        }
    }

    func testParseBackupRejectsUnparseableDate() {
        let data = backupJSON(backupEntry(id: "bad-date", date: "11.07.2026"))

        XCTAssertThrowsError(try BackupService.parseBackup(data: data)) { error in
            XCTAssertEqual(error as? BackupService.BackupError, .invalidExpense)
        }
    }

    func testParseBackupRejectsMalformedJSON() {
        XCTAssertThrowsError(try BackupService.parseBackup(data: Data("{not json".utf8))) { error in
            XCTAssertTrue(error is DecodingError, "expected a decoding failure, got \(error)")
        }
    }

    func testParseBackupRejectsEntryMissingRequiredField() {
        // `amount` omitted entirely — decoding must fail rather than default to zero.
        let data = backupJSON("""
        {"id":"no-amount","description":"Coffee","date":"2026-07-11",
         "splitMode":"percent","splitValue":50}
        """)

        XCTAssertThrowsError(try BackupService.parseBackup(data: data)) { error in
            XCTAssertTrue(error is DecodingError, "expected a decoding failure, got \(error)")
        }
    }

    func testParseBackupAcceptsEmptyBackup() throws {
        // An empty array is valid input: it means "replace everything with nothing".
        XCTAssertEqual(try BackupService.parseBackup(data: Data("[]".utf8)).count, 0)
    }

    func testParseBackupAcceptsEntryWithoutCreatedAt() throws {
        // `createdAt` is optional in ExpenseBackup; older exports omit it.
        let data = backupJSON("""
        {"id":"legacy","amount":10.5,"description":"Coffee","date":"2026-07-11",
         "splitMode":"percent","splitValue":50}
        """)

        let imported = try BackupService.parseBackup(data: data)
        XCTAssertEqual(imported.count, 1)
        XCTAssertNil(imported[0].createdAt)
        XCTAssertNotNil(imported[0].toExpense())
    }

    func testParseBackupFallsBackToPercentForUnknownSplitMode() throws {
        // `toExpense()` defaults an unrecognized mode to .percent rather than failing,
        // so such a backup is accepted; this pins that documented behaviour.
        let data = backupJSON("""
        {"id":"odd-mode","amount":10.5,"description":"Coffee","date":"2026-07-11",
         "splitMode":"quarters","splitValue":50,"createdAt":"2026-07-11T09:00:00Z"}
        """)

        let expense = try XCTUnwrap(BackupService.parseBackup(data: data).first?.toExpense())
        XCTAssertEqual(expense.splitMode, .percent)
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

    // MARK: - Voice consent lifecycle
    //
    // Consent is tied to the Voice Mode toggle: there is no separate withdrawal action,
    // so turning Voice Mode off must clear the stored consent. If consent ever outlived
    // the enabled state, re-enabling would silently skip the disclosure sheet.

    /// Builds a view model that already has a verified key, then restores whatever was in
    /// UserDefaults when the test finishes.
    private func makeVoiceReadyViewModel() -> (SettingsViewModel, Data?) {
        let previous = UserDefaults.standard.data(forKey: VoiceSettings.storageKey)
        let viewModel = SettingsViewModel()
        // Simulator clones can inherit consent from manual QA. Each test must
        // establish its own consent state rather than trust persisted settings.
        viewModel.voiceSettings = .default
        viewModel.hasSavedVoiceAPIKey = true
        viewModel.voiceSettings.apiKeySuffix = "7mQ2"
        viewModel.voiceSettings.verifiedAt = Date()
        return (viewModel, previous)
    }

    private func restoreVoiceSettings(_ previous: Data?) {
        if let previous {
            UserDefaults.standard.set(previous, forKey: VoiceSettings.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: VoiceSettings.storageKey)
        }
    }

    func testDisablingVoiceModeRevokesConsent() {
        let (viewModel, previous) = makeVoiceReadyViewModel()
        defer { restoreVoiceSettings(previous) }

        viewModel.acceptVoiceConsent()
        viewModel.voiceEnabled = true
        XCTAssertTrue(viewModel.voiceEnabled)
        XCTAssertTrue(viewModel.hasVoiceConsent)

        viewModel.voiceEnabled = false

        XCTAssertFalse(viewModel.voiceEnabled)
        XCTAssertFalse(viewModel.hasVoiceConsent, "turning Voice Mode off must revoke consent")
    }

    func testEnablingVoiceModeWithoutConsentDoesNotEnable() {
        let (viewModel, previous) = makeVoiceReadyViewModel()
        defer { restoreVoiceSettings(previous) }

        // No acceptVoiceConsent() call: the UI shows the disclosure instead of enabling.
        viewModel.voiceEnabled = true

        XCTAssertFalse(viewModel.voiceEnabled)
        XCTAssertFalse(viewModel.hasVoiceConsent)
    }

    func testReEnablingAfterDisableRequiresConsentAgain() {
        let (viewModel, previous) = makeVoiceReadyViewModel()
        defer { restoreVoiceSettings(previous) }

        viewModel.acceptVoiceConsent()
        viewModel.voiceEnabled = true
        viewModel.voiceEnabled = false

        // Flipping the switch back on without re-accepting must not re-enable.
        viewModel.voiceEnabled = true
        XCTAssertFalse(viewModel.voiceEnabled)

        // Accepting the disclosure again restores it.
        viewModel.acceptVoiceConsent()
        viewModel.voiceEnabled = true
        XCTAssertTrue(viewModel.voiceEnabled)
        XCTAssertTrue(viewModel.hasVoiceConsent)
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
