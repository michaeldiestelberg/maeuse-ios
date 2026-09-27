// macOS test adapter: runs the production interpreter/models on synthetic data.
// Speech and UI stay in the iOS app; this harness makes no OpenAI calls.
import Foundation
import FoundationModels

enum VoiceProvider: String, Codable { case appleLocal, openAI }
final class LanguageManager {
    static let shared = LanguageManager()
    var activeLanguageCode = "en"
    var activeLocale: Locale { Locale(identifier: activeLanguageCode) }
}
func loc(_ text: String) -> String { text }
enum VoiceModeViewModel { static func todayISOString() -> String { "2026-09-27" } }
enum LocalVoiceAvailability {
    case available, unavailable
    static var current: Self { SystemLanguageModel.default.availability == .available ? .available : .unavailable }
    var message: String { "Apple model unavailable" }
}
struct LocalVoiceError: LocalizedError { let message: String; var errorDescription: String? { message } }

@main struct Integration {
    @MainActor static func main() async {
        guard LocalVoiceAvailability.current == .available else {
            print("Apple Intelligence must be enabled with the on-device model downloaded.")
            exit(2)
        }
        let context = #"App-provided initial workspace, not a spoken request. Keep these drafts and IDs when processing the next spoken request. Removed IDs must stay removed; an explicit re-add must use a new ID. Do not respond to this note. {"expenses":[{"id":"921B7C2E-7A90-4777-88DF-6ECCAA47CA11","title":"Coffee","amount":4,"date_iso":"2026-09-27","split_mode":"percent","split_value":50}],"removed_ids":[],"clarification_question":""}"#
        let cases: [(String, String, String?, [Double?], [Double], [String])] = [
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
        var failed = 0
        for (lang,text,ctx,amounts,shares,dates) in cases {
            LanguageManager.shared.activeLanguageCode = lang
            do {
                let result = try await AppleExpenseInterpreter.interpret(text, context: ctx)
                let ok = result.expenses.map(\.amount) == amounts && result.expenses.map { $0.splitValue ?? 50 } == shares && result.expenses.map { $0.dateISO ?? "" } == dates
                print("\(ok ? "PASS" : "FAIL"): \(text)")
                if !ok { failed += 1; print(result) }
            } catch { failed += 1; print("FAIL: \(text): \(error)") }
        }
        print("Integration checks: \(cases.count-failed)/\(cases.count) passed")
        if failed > 0 { exit(1) }
    }
}
