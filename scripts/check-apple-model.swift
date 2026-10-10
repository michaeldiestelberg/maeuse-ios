// macOS test adapter: runs the production interpreter/models on synthetic data.
// Speech and UI stay in the iOS app; this harness makes no OpenAI calls.
import Foundation
import FoundationModels
import Darwin

enum VoiceProvider: String, Codable { case appleLocal, openAI }
final class LanguageManager {
    static let shared = LanguageManager()
    var activeLanguageCode = "en"
    var activeLocale: Locale { Locale(identifier: activeLanguageCode) }
}
func loc(_ text: String, _ args: CVarArg...) -> String {
    let formats = ["VoiceUnassignedRatio": "%@/%@ – assignment needed", "VoiceUserFixedPending": "I pay €%@ – total needed"]
    return args.isEmpty ? text : String(format: formats[text] ?? text, arguments: args)
}
enum VoiceModeViewModel { static func todayISOString() -> String { "2026-09-27" } }
enum LocalVoiceAvailability {
    case available, unavailable
    static var current: Self { SystemLanguageModel.default.availability == .available ? .available : .unavailable }
    var message: String { "Apple model unavailable" }
}
struct LocalVoiceError: LocalizedError { let message: String; var errorDescription: String? { message } }

@main struct Integration {
    @MainActor static func main() async {
        setbuf(stdout, nil)
        print("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Model availability: \(SystemLanguageModel.default.availability)")
        guard LocalVoiceAvailability.current == .available else {
            print("Apple Intelligence must be enabled with the on-device model downloaded.")
            exit(2)
        }
        let context = #"App-provided initial workspace, not a spoken request. Keep these drafts and IDs when processing the next spoken request. Removed IDs must stay removed; an explicit re-add must use a new ID. Do not respond to this note. {"expenses":[{"id":"921B7C2E-7A90-4777-88DF-6ECCAA47CA11","title":"Coffee","amount":4,"date_iso":"2026-09-27","split_mode":"percent","split_value":50}],"removed_ids":[],"clarification_question":""}"#
        var cases: [(String, String, String?, [Double?], [Double], [String])] = [
            ("en", "Coffee for four euros fifty and flowers for twelve euros yesterday.", nil, [4.5,12], [50,50], ["2026-09-26","2026-09-26"]),
            ("de", "Kaffee für vier Euro fünfzig und Blumen für zwölf Euro gestern.", nil, [4.5,12], [50,50], ["2026-09-26","2026-09-26"]),
            ("en", "Dinner 64 euros. My partner owes 20 euros.", nil, [64], [20], ["2026-09-27"]),
            ("de", "Abendessen 64 Euro. Mein Partner zahlt 25 Prozent.", nil, [64], [25], ["2026-09-27"]),
            ("en", "Coffee", nil, [nil], [50], ["2026-09-27"]),
            ("en", "Groceries 84.30 euros today", nil, [84.3], [50], ["2026-09-27"]),
            ("en", "The coffee was five euros, not four.", context, [5], [50], ["2026-09-27"]),
            ("en", "Remove the coffee.", context, [], [], []),
            ("en", "Add another coffee for three euros fifty.", context, [4,3.5], [50,50], ["2026-09-27","2026-09-27"]),
            ("en", "For the coffee my partner pays one euro.", context, [4], [1], ["2026-09-27"])
        ]
        // Held-out formulations: kept out of production prompts and tool examples.
        if ProcessInfo.processInfo.environment["MAEUSE_MODEL_VARIANTS"] == "1" {
            cases += [
                ("de", "Parken kostet 9,80 Euro. Mein Partner übernimmt drei Euro.", nil, [9.8], [3], ["2026-09-27"]),
                ("de", "Eintritt 28 Euro, davon zahle ich sieben Euro.", nil, [28], [21], ["2026-09-27"]),
                ("en", "Lunch cost seventeen euros fifty. I'm not sure about splitting it.", nil, [17.5], [50], ["2026-09-27"]),
                ("de", "Der Kaffee hat vier Euro gekostet.", nil, [4], [50], ["2026-09-27"]),
                ("en", "Bread 2.60 euros and milk 1.90 euros.", nil, [2.6, 1.9], [50,50], ["2026-09-27","2026-09-27"]),
                ("en", "My share is 60 percent for the coffee.", context, [4], [40], ["2026-09-27"]),
                ("en", "For the coffee I pay one euro.", context, [4], [3], ["2026-09-27"]),
                ("de", "Buch für sechzehn Euro vorgestern.", nil, [16], [50], ["2026-09-25"]),
                ("en", "Tea cost two euros and cake five euros yesterday.", nil, [2,5], [50,50], ["2026-09-26","2026-09-26"]),
                ("de", "Tram drei Euro zwanzig, vor zwei Tagen.", nil, [3.2], [50], ["2026-09-25"]),
                ("en", "A notebook for six euros the day before yesterday.", nil, [6], [50], ["2026-09-25"]),
                ("de", "Die Fahrt kostet acht Euro. Meine Partnerin zahlt vierzig Prozent.", nil, [8], [40], ["2026-09-27"])
            ]
        }
        let fixedVariantTexts: Set<String> = ["Parken kostet 9,80 Euro. Mein Partner übernimmt drei Euro.", "Eintritt 28 Euro, davon zahle ich sieben Euro.", "For the coffee I pay one euro."]
        var failed = 0
        for (lang,text,ctx,amounts,shares,dates) in cases {
            LanguageManager.shared.activeLanguageCode = lang
            do {
                let started = Date()
                let result = try await AppleExpenseInterpreter.interpret(text, context: ctx)
                let expectedModes = shares.map { _ in text.contains("owes 20 euros") || text.contains("pays one euro") || fixedVariantTexts.contains(text) ? "fixed" : "percent" }
                let ok = result.expenses.map(\.amount) == amounts && result.expenses.map(\.splitValue) == shares.map { Optional($0) } &&
                    result.expenses.map { $0.dateISO ?? "" } == dates && result.expenses.map(\.splitMode) == expectedModes.map { Optional($0) } &&
                    zip(result.expenses, amounts).allSatisfy { $0.0.draft.isReadyForSaving == ($0.1 != nil) }
                print("\(ok ? "PASS" : "FAIL"): \(text) [\(String(format: "%.2f", Date().timeIntervalSince(started)))s]")
                if !ok { failed += 1; print(result) }
            } catch { failed += 1; print("FAIL: \(text): \(error)") }
        }
        // Real on-device model checks supplement the deterministic iOS tests.
        // No quoted-value parser or mocked model response is used here.
        func contextFor(_ payload: VoiceWorkspaceSyncPayload) throws -> String {
            let rows: [[String: Any]] = payload.expenses.map { row in
                ["id": row.id, "title": row.title as Any? ?? NSNull(), "amount": row.amount as Any? ?? NSNull(),
                 "date_iso": row.dateISO as Any? ?? NSNull(), "split_mode": row.splitMode as Any? ?? NSNull(),
                 "split_value": row.splitValue as Any? ?? NSNull(), "missing_fields": row.missingFields.map(\.rawValue),
                 "split_intent": row.splitIntent as Any? ?? NSNull(), "pending_user_fixed_share": row.pendingUserFixedShare as Any? ?? NSNull()]
            }
            let data = try JSONSerialization.data(withJSONObject: ["expenses": rows,
                "clarification_question": payload.clarificationQuestion, "last_request": payload.userUnderstanding])
            return String(decoding: data, as: UTF8.self)
        }
        var extraCount = 0
        func check(_ label: String, _ ok: Bool, _ result: VoiceWorkspaceSyncPayload) {
            extraCount += 1
            print("\(ok ? "PASS" : "FAIL"): \(label)")
            if !ok { failed += 1; print(result) }
        }
        LanguageManager.shared.activeLanguageCode = "de"
        do {
            let sentence = "Tesla Supercharger hat mich 73 € gekostet das war bereits vor drei Tagen und ich würde es gern 7030 teilen"
            let tesla = try await AppleExpenseInterpreter.interpret(sentence, context: nil)
            check("Tesla 73 / relative -3 / unassigned 70:30", tesla.expenses.count == 1 && tesla.expenses[0].amount == 73 &&
                tesla.expenses[0].dateISO == "2026-09-24" && tesla.expenses[0].missingFields.contains(.split) &&
                tesla.expenses[0].splitIntent?.contains("70/30") == true && !tesla.expenses[0].draft.isReadyForSaving, tesla)
            let clarified = try await AppleExpenseInterpreter.interpret("Ich übernehme 70 Prozent, mein Partner 30.", context: contextFor(tesla))
            check("Tesla follow-up assignment", clarified.expenses.count == 1 && clarified.expenses[0].amount == 73 &&
                clarified.expenses[0].dateISO == "2026-09-24" && clarified.expenses[0].splitValue == 30 &&
                clarified.expenses[0].draft.isReadyForSaving, clarified)
            let missingSplit = try await AppleExpenseInterpreter.interpret("Kaffee 4 Euro.", context: nil)
            check("Unstated share defaults 50/50", missingSplit.expenses.count == 1 && missingSplit.expenses[0].splitValue == 50 &&
                missingSplit.expenses[0].draft.isReadyForSaving, missingSplit)
            let uncertainDate = try await AppleExpenseInterpreter.interpret("Kaffee 4 Euro, am vierunddreißigsten Oktober.", context: nil)
            check("Explicit impossible date remains open", uncertainDate.expenses.count == 1 && uncertainDate.expenses[0].amount == 4 &&
                !uncertainDate.expenses[0].draft.isReadyForSaving, uncertainDate)
        } catch { failed += 1; print("FAIL: semantic follow-ups: \(error)") }
        print("Integration checks: \(cases.count+extraCount-failed)/\(cases.count+extraCount) passed")
        if failed > 0 { exit(1) }
    }
}
