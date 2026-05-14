import XCTest
@testable import Maeuse

@MainActor
final class RealtimeVoiceWorkspaceTests: XCTestCase {
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
        XCTAssertEqual(viewModel.takeawayText, "1 expense · 10.00 € total · 5.00 € partner")
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
    }

    func testNormalizesIncompleteDraftsForSaving() {
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

        XCTAssertEqual(expenses.count, 2)
        XCTAssertEqual(expenses[0].desc, "Untitled expense")
        XCTAssertEqual(expenses[0].amount, 12.35)
        XCTAssertEqual(expenses[0].splitMode, .percent)
        XCTAssertEqual(expenses[0].splitValue, 50)
        XCTAssertEqual(expenses[1].desc, "Bakery")
        XCTAssertEqual(expenses[1].amount, 0)
        XCTAssertEqual(expenses[1].splitMode, .fixed)
        XCTAssertEqual(expenses[1].splitValue, 2)
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
