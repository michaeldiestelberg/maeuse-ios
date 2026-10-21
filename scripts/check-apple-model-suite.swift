// Broad accuracy suite for the Apple interpreter: 90 dictation-style requests in English
// and German, run against the real on-device model. Run scripts/check-apple-model-suite.sh;
// an optional argument runs only requests containing that text.
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
enum VoiceModeViewModel { static var referenceDate = "2026-09-27"; static func todayISOString() -> String { referenceDate } }
enum LocalVoiceAvailability {
    case available, unavailable
    static var current: Self { SystemLanguageModel.default.availability == .available ? .available : .unavailable }
    var message: String { "Apple model unavailable" }
}
struct LocalVoiceError: LocalizedError { let message: String; var errorDescription: String? { message } }

struct Exp { let title: String; let amount: Double?; let share: Double; let mode: String; let date: String }
func e(_ t: String, _ a: Double?, _ s: Double = 50, _ m: String = "percent", d: String = "2026-09-27") -> Exp { Exp(title: t, amount: a, share: s, mode: m, date: d) }

func ctx(_ rows: [(String, String, Double?)]) -> String {
    let items = rows.map { r -> [String: Any] in
        ["id": r.0, "title": r.1, "amount": r.2 as Any? ?? NSNull(), "date_iso": "2026-09-27", "split_mode": "percent", "split_value": 50, "missing_fields": r.2 == nil ? ["amount"] : []]
    }
    let data = try! JSONSerialization.data(withJSONObject: ["expenses": items, "removed_ids": [], "clarification_question": ""])
    return "App-provided initial workspace, not a spoken request. Keep these drafts and IDs when processing the next spoken request. Removed IDs must stay removed; an explicit re-add must use a new ID. Do not respond to this note. " + String(data: data, encoding: .utf8)!
}

let enCtx = ctx([("A1", "Coffee", 4), ("B2", "Flowers", 12)])
let deCtx = ctx([("A1", "Kaffee", 4), ("B2", "Blumen", 12)])
let uuidCtx = ctx([("921B7C2E-7A90-4777-88DF-6ECCAA47CA11", "Coffee", 4)])
let parkCtx = ctx([("P1", "Parking", nil)])

let cases: [(String, String, String?, [Exp])] = [
    // Original checks: spoken words and a workspace with a model-unseen ID
    ("en", "Coffee for four euros fifty and flowers for twelve euros yesterday.", nil, [e("coffee", 4.5, d: "2026-09-26"), e("flower", 12, d: "2026-09-26")]),
    ("de", "Kaffee für vier Euro fünfzig und Blumen für zwölf Euro gestern.", nil, [e("kaffee", 4.5, d: "2026-09-26"), e("blume", 12, d: "2026-09-26")]),
    ("en", "Dinner 64 euros. My partner owes 20 euros.", nil, [e("dinner", 64, 20, "fixed")]),
    ("de", "Abendessen 64 Euro. Mein Partner zahlt 25 Prozent.", nil, [e("abendessen", 64, 25)]),
    ("en", "Coffee", nil, [e("coffee", nil)]),
    ("en", "Groceries 84.30 euros today", nil, [e("grocer", 84.3)]),
    ("en", "The coffee was five euros, not four.", uuidCtx, [e("coffee", 5)]),
    ("en", "Remove the coffee.", uuidCtx, []),
    ("en", "Add another coffee for three euros fifty.", uuidCtx, [e("coffee", 4), e("coffee", 3.5)]),
    ("en", "For the coffee my partner pays one euro.", uuidCtx, [e("coffee", 4, 1, "fixed")]),
    // Dictation-formatted requests
    // English, formatted like iOS dictation output
    ("en", "Coffee for €4.50 and flowers for €12 yesterday", nil, [e("coffee", 4.5, d: "2026-09-26"), e("flower", 12, d: "2026-09-26")]),
    ("en", "Groceries at Rewe €84.30", nil, [e("grocer", 84.3)]),
    ("en", "Dinner €64, my partner owes €20", nil, [e("dinner", 64, 20, "fixed")]),
    ("en", "Lunch 15 euros and taxi 22 euros and cinema tickets 24 euros", nil, [e("lunch", 15), e("taxi", 22), e("cinema", 24)]),
    ("en", "I paid €120 for the electricity bill, split 50/50", nil, [e("electric", 120)]),
    ("en", "Netflix €17.99, my partner pays everything", nil, [e("netflix", 17.99, 100)]),
    ("en", "Pizza delivery €32 last Friday", nil, [e("pizza", 32, d: "2026-09-25")]),
    ("en", "Concert tickets €150 on September 3rd", nil, [e("concert", 150, d: "2026-09-03")]),
    ("en", "Bakery 6 euros 80", nil, [e("bakery", 6.8)]),
    ("en", "Gas station €65, split evenly", nil, [e("gas", 65)]),
    ("en", "Coffee €3.20 and a croissant €2.50 this morning", nil, [e("coffee", 3.2), e("croissant", 2.5)]),
    ("en", "Haircut €35, that's just for me", nil, [e("haircut", 35, 0)]),
    ("en", "Train tickets for €58.90 the day before yesterday", nil, [e("train", 58.9, d: "2026-09-25")]),
    ("en", "Drugstore €23.40 and my partner pays 30%", nil, [e("drugstore", 23.4, 30)]),
    ("en", "Spent 45 euros on groceries and 12 euros on wine", nil, [e("grocer", 45), e("wine", 12)]),
    ("en", "Rent €1,200, my partner pays €600", nil, [e("rent", 1200, 600, "fixed")]),
    ("en", "Uh so I bought some coffee beans for like €14", nil, [e("coffee", 14)]),
    // German
    ("de", "Kaffee für 4,50 € und Blumen für 12 € gestern", nil, [e("kaffee", 4.5, d: "2026-09-26"), e("blume", 12, d: "2026-09-26")]),
    ("de", "Abendessen 64 €, mein Partner zahlt 25 %", nil, [e("abendessen", 64, 25)]),
    ("de", "Einkauf bei Rewe 84,30 €", nil, [e("rewe", 84.3)]),
    ("de", "Tanken 65 €, wir teilen halbe halbe", nil, [e("tank", 65)]),
    ("de", "Miete 1.200 €, meine Freundin zahlt 600 €", nil, [e("miete", 1200, 600, "fixed")]),
    ("de", "Pizza 28 € letzten Freitag", nil, [e("pizza", 28, d: "2026-09-25")]),
    ("de", "Kino 24 € am 3. September", nil, [e("kino", 24, d: "2026-09-03")]),
    ("de", "Drogerie 18,90 € und Bäcker 7,20 € und Apotheke 12 €", nil, [e("drogerie", 18.9), e("bäcker", 7.2), e("apotheke", 12)]),
    ("de", "Strom 89 €, das zahlt mein Partner komplett", nil, [e("strom", 89, 100)]),
    ("de", "Friseur 35 €, das zahle ich alleine", nil, [e("friseur", 35, 0)]),
    ("de", "Brötchen 4 Euro 80", nil, [e("brötchen", 4.8)]),
    ("de", "Fahrkarte 3,40 € vorgestern", nil, [e("fahrkarte", 3.4, d: "2026-09-25")]),
    ("de", "Ich habe 23 € für Wein ausgegeben", nil, [e("wein", 23)]),
    // Corrections against an existing workspace
    ("en", "Actually the flowers were €15", enCtx, [e("coffee", 4), e("flower", 15)]),
    ("en", "Change the date of the coffee to yesterday", enCtx, [e("coffee", 4, d: "2026-09-26"), e("flower", 12)]),
    ("en", "My partner pays all of the flowers", enCtx, [e("coffee", 4), e("flower", 12, 100)]),
    ("en", "Delete the flowers", enCtx, [e("coffee", 4)]),
    ("en", "Also a taxi for €18", enCtx, [e("coffee", 4), e("flower", 12), e("taxi", 18)]),
    ("en", "It was €7", parkCtx, [e("parking", 7)]),
    ("de", "Der Kaffee hat 3,80 € gekostet", deCtx, [e("kaffee", 3.8), e("blume", 12)]),
    ("de", "Die Blumen hat mein Partner komplett bezahlt", deCtx, [e("kaffee", 4), e("blume", 12, 100)]),
    ("de", "Lösche den Kaffee", deCtx, [e("blume", 12)]),
    ("de", "Und noch ein Taxi für 18 €", deCtx, [e("kaffee", 4), e("blume", 12), e("taxi", 18)]),
    // Held out from tuning
    ("en", "Bought groceries for €56.70 on Saturday", nil, [e("grocer", 56.7, d: "2026-09-26")]),
    ("en", "Parking €4", nil, [e("parking", 4)]),
    ("en", "Pharmacy €12.35 yesterday, my partner pays €5", nil, [e("pharmacy", 12.35, 5, "fixed", d: "2026-09-26")]),
    ("en", "€30 for the birthday present, my partner pays all of it", nil, [e("present", 30, 100)]),
    ("en", "Cleaning supplies 19 euros 99", nil, [e("cleaning", 19.99)]),
    ("en", "Water bill €42.10 on the 15th", nil, [e("water", 42.1, d: "2026-09-15")]),
    ("en", "Restaurant with friends €78, I'll pay 60%", nil, [e("restaurant", 78, 40)]),
    ("en", "Bus ticket €3.10 and train ticket €12.40", nil, [e("bus", 3.1), e("train", 12.4)]),
    ("en", "Ice cream €6.50 and my partner owes me €3", nil, [e("ice", 6.5, 3, "fixed")]),
    ("en", "Shoes €89.95 last Wednesday", nil, [e("shoe", 89.95, d: "2026-09-23")]),
    ("en", "Phone bill €25 on September 1st", nil, [e("phone", 25, d: "2026-09-01")]),
    ("de", "Supermarkt 43,20 € am Samstag", nil, [e("supermarkt", 43.2, d: "2026-09-26")]),
    ("de", "Parkhaus 6 €", nil, [e("parkhaus", 6)]),
    ("de", "Geschenk für Mama 25 €, meine Frau zahlt die Hälfte", nil, [e("geschenk", 25)]),
    ("de", "Apotheke 9,95 € gestern, mein Mann übernimmt alles", nil, [e("apotheke", 9.95, 100, d: "2026-09-26")]),
    ("de", "Pizza 18 Euro 50 und Getränke 7 €", nil, [e("pizza", 18.5), e("getränk", 7)]),
    ("de", "Stromrechnung 120 € am 15. September", nil, [e("strom", 120, d: "2026-09-15")]),
    ("de", "Kinokarten 22 €, ich zahle 40 Prozent", nil, [e("kino", 22, 60)]),
    ("de", "Taxi 14 € vorgestern, das ist nur für mich", nil, [e("taxi", 14, 0, d: "2026-09-25")]),
    ("de", "Schuhe 79,90 € letzten Donnerstag", nil, [e("schuh", 79.9, d: "2026-09-24")]),
    ("en", "The coffee was actually €4.80", enCtx, [e("coffee", 4.8), e("flower", 12)]),
    ("en", "My partner pays €6 for the flowers", enCtx, [e("coffee", 4), e("flower", 12, 6, "fixed")]),
    ("en", "Remove the coffee", enCtx, [e("flower", 12)]),
    ("de", "Die Blumen waren vorgestern", deCtx, [e("kaffee", 4), e("blume", 12, d: "2026-09-25")]),
    ("de", "Noch ein Brot für 3,20 €", deCtx, [e("kaffee", 4), e("blume", 12), e("brot", 3.2)]),
    // Harder phrasings: paraphrased shares, spelled amounts, unusual dates
    ("de", "Abendessen 80 €, meine Partnerin übernimmt 30 Prozent davon", nil, [e("abendessen", 80, 30)]),
    ("en", "Hotel €240, my partner covers a quarter", nil, [e("hotel", 240, 25)]),
    ("en", "Groceries 56 euros, my girlfriend owes me 18", nil, [e("grocer", 56, 18, "fixed")]),
    ("de", "Taxi 30 € und davon zahlt mein Freund 10 €", nil, [e("taxi", 30, 10, "fixed")]),
    ("en", "Concert €90, I'll cover two thirds", nil, [e("concert", 90, 33.33)]),
    ("en", "Gym membership thirty-nine ninety", nil, [e("gym", 39.9)]),
    ("de", "Pizza neunzehn Euro neunzig gestern", nil, [e("pizza", 19.9, d: "2026-09-26")]),
    ("en", "Brunch €42 on the 5th, split it down the middle", nil, [e("brunch", 42, d: "2026-09-05")]),
    ("de", "Wocheneinkauf 112,40 €, Hälfte übernimmt meine Frau", nil, [e("einkauf", 112.4)]),
    ("en", "Dentist €120, I'm paying 75 percent of that", nil, [e("dentist", 120, 25)]),
    ("de", "Blumen für Oma 25 €, die zahle ich komplett selbst", nil, [e("blume", 25, 0)]),
    ("en", "Takeaway €36 on Thursday and my partner pays 12 of it", nil, [e("takeaway", 36, 12, "fixed", d: "2026-09-24")]),
    ("de", "Kinoabend 31 €, mein Mann zahlt 40 %", nil, [e("kino", 31, 40)]),
    ("en", "Electricity 94 euros, partner owes me nothing for it", nil, [e("electric", 94, 0)]),
    ("de", "Fitnessstudio neununddreißig Euro, teilen wir fifty-fifty", nil, [e("fitness", 39)]),
]

// Misreadings by the current on-device model. They are reported but do not fail the
// check, so an improved model shows up as unexpected passes.
let knownLimits: Set<String> = [
    // Shares the pipeline leaves open for the user to assign.
    "Groceries 56 euros, my girlfriend owes me 18",
    "Taxi 30 € und davon zahlt mein Freund 10 €",
    "Takeaway €36 on Thursday and my partner pays 12 of it",
    "Concert €90, I'll cover two thirds",
    "Gym membership thirty-nine ninety",
    // Shares the model does not recognize.
    "Hotel €240, my partner covers a quarter",
    "Electricity 94 euros, partner owes me nothing for it",
    "Die Blumen hat mein Partner komplett bezahlt",
    // Dates the model miscounts.
    "Bought groceries for €56.70 on Saturday",
    "Shoes €89.95 last Wednesday",
    "Die Blumen waren vorgestern",
]

/// What the partner owes, so "0%" and "€0" or "50%" of €64 and "€32" compare equal.
func partnerShare(_ amount: Double?, _ mode: String?, _ value: Double?) -> Double? {
    guard let amount else { return nil }
    let value = value ?? 50
    let euros = (mode ?? "percent") == "fixed" ? value : amount * value / 100
    return (euros * 100).rounded() / 100
}

@main struct Integration {
    @MainActor static func main() async {
        guard LocalVoiceAvailability.current == .available else { print("Apple Intelligence must be enabled with the on-device model downloaded."); exit(2) }
        let filter = CommandLine.arguments.dropFirst().first
        var failed = 0, known = 0, run = 0
        var slowest = Duration.zero, total = Duration.zero
        for (lang, text, context, expected) in cases {
            if let filter, !text.localizedCaseInsensitiveContains(filter) { continue }
            run += 1
            LanguageManager.shared.activeLanguageCode = lang
            let started = ContinuousClock.now
            defer {
                let elapsed = ContinuousClock.now - started
                total += elapsed
                slowest = max(slowest, elapsed)
            }
            do {
                let result = try await AppleExpenseInterpreter.interpret(text, context: context)
                let got = result.expenses
                var problems: [String] = []
                if got.count != expected.count { problems.append("count \(got.count)≠\(expected.count)") }
                for (g, x) in zip(got, expected) {
                    if !(g.title ?? "").lowercased().contains(x.title) { problems.append("title '\(g.title ?? "")'") }
                    if g.amount != x.amount { problems.append("amount \(g.amount.map { "\($0)" } ?? "nil")≠\(x.amount.map { "\($0)" } ?? "nil")") }
                    let sameShare = x.amount == nil ? (g.splitValue ?? 50) == x.share && (g.splitMode ?? "percent") == x.mode
                        : partnerShare(g.amount, g.splitMode, g.splitValue) == partnerShare(x.amount, x.mode, x.share)
                    if !sameShare { problems.append("split \(g.splitMode ?? "-") \(g.splitValue ?? -1)≠\(x.mode) \(x.share)") }
                    if (g.dateISO ?? "") != x.date { problems.append("date \(g.dateISO ?? "nil")≠\(x.date)") }
                }
                let summary = got.map { "[\($0.title ?? "") \($0.amount.map { "\($0)" } ?? "nil") \($0.splitMode ?? "") \($0.splitValue ?? -1) \($0.dateISO ?? "")]" }.joined(separator: " ")
                if problems.isEmpty { print("\(knownLimits.contains(text) ? "PASS! (known limit passed)" : "PASS ") \(text)  →  \(summary)") }
                else if knownLimits.contains(text) { known += 1; print("KNOWN \(text)  →  \(summary)  ⟵ \(problems.joined(separator: "; "))") }
                else { failed += 1; print("FAIL  \(text)  →  \(summary)  ⟵ \(problems.joined(separator: "; "))") }
            } catch {
                failed += 1
                print("ERROR \(text)  →  \(error.localizedDescription)")
            }
        }
        print("Integration checks: \(run - failed - known)/\(run) passed, \(known) known model limits")
        if run > 0 {
            print("Time per request: \((total / run).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))) average, \(slowest.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))) slowest")
        }
        if failed > 0 { exit(1) }
    }
}
