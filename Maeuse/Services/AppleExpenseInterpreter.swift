import Foundation
import FoundationModels

/// Dictation writes "€4.50" or "4,50 €", and "4 Euro 80" is one price. The model reads
/// and quotes one canonical spelling, so literal price checks see a single number.
enum LocalTranscript {
    static func normalized(_ text: String, language: String = LanguageManager.shared.activeLanguageCode) -> String {
        let unit = language == "de" ? "Euro" : "euros"
        let decimal = language == "de" ? "," : "."
        func cents(_ digits: String) -> String { digits.count == 1 ? "0" + digits : digits }
        // A trailing symbol binds first, so "3 € 5" stays one price.
        var result = text
            .replacingOccurrences(of: #"([0-9])\s*(?:€|\bEUR\b)"#, with: "$1 \(unit)", options: .regularExpression)
            .replacingOccurrences(of: #"€\s*([0-9]+(?:[.,][0-9]+)*)"#, with: "$1 \(unit)", options: .regularExpression)
        result = replacing(#"(?<![0-9.,])([0-9]+) euros? (?:(?:and|und) )?([0-9]{1,2}) cents?\b"#, in: result) {
            "\($0[1])\(decimal)\(cents($0[2])) \(unit)"
        }
        return replacing(#"(?<![0-9.,])([0-9]+) euros? ([0-9]{1,2})(?![0-9.,]|\s*(?:%|percent|prozent|euro|cent))"#, in: result) {
            "\($0[1])\(decimal)\(cents($0[2])) \(unit)"
        }
    }

    private static func replacing(_ pattern: String, in text: String, _ transform: ([String]) -> String) -> String {
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
            let groups = (0..<match.numberOfRanges).map { result.substring(with: match.range(at: $0)) }
            result.replaceCharacters(in: match.range, with: transform(groups))
        }
        return result as String
    }
}

@available(iOS 26.0, *)
@Generable
enum LocalWorkspaceAction { case add, correct, remove, rename }

@available(iOS 26.0, *)
@Generable
enum LocalShareKind {
    case unchanged, notMentioned, uncertain, partnerPercent, userPercent, partnerFixed, userFixed, unassignedRatio
}

@available(iOS 26.0, *)
struct LocalExpenseUpdate {
    var action: LocalWorkspaceAction
    var expenseNumber: Int
    var title: String?
    var amount: Double?
    var dateISO: String?
    var dayOffset: Int?
    var dateUnclear: Bool
    var shareKind: LocalShareKind
    var shareValue: Double?
    var secondShareValue: Double?
    var amountUnclear: Bool = false
}

@available(iOS 26.0, *)
struct LocalExpenseInterpretation {
    var updates: [LocalExpenseUpdate]
    var clarificationQuestion: String
}

@available(iOS 26.0, *)
@Generable
private struct LocalWorkspaceIntent {
    @Generable enum Action { case add, totalPrice, date, share, multiple, remove, rename, clarify }
    var action: Action
    @Guide(description: "Existing number for any edit/removal; zero only for add or unclear target.", .range(0...10)) var expenseNumber: Int
}

@available(iOS 26.0, *)
@Generable
private struct LocalSourcePurchase {
    @Guide(description: "Short purchase/merchant name, without price/date/share.") var title: String
    @Guide(description: "Exact quote of the total purchase price, including currency and original number words; empty if missing. No personal contribution or ratio.") var priceText: String
}
@available(iOS 26.0, *) @Generable private struct LocalSourcePlan {
    @Guide(description: "Only explicitly mentioned new purchases, in spoken order.", .count(0...10)) var purchases: [LocalSourcePurchase]
}
@available(iOS 26.0, *) @Generable struct LocalMoneySource {
    @Guide(description: "Copy source bytes exactly: digits stay digits, punctuation stays unchanged, number words stay words. Continuous total purchase price quote with currency; empty if absent.") var priceText: String
    @Guide(description: "Exact currency word/symbol attached to that copied purchase total; empty if absent.") var currencyText: String
}
@available(iOS 26.0, *) @Generable private struct LocalDatePresence {
    @Guide(description: "True ONLY for an explicitly stated calendar date or relative-day expression. Prices/numbers and purchase names are not dates.") var hasDate: Bool
}
@available(iOS 26.0, *) @Generable private struct LocalSharePresence {
    @Guide(description: "Minimal exact continuous source clause for the personal contribution or requested sharing ratio. Empty if absent. Preserve words and digits; exclude dates and purchase-total placeholders.") var quote: String
    @Generable enum Kind { case absent, contribution, ratio, whole }
    @Guide(description: "absent if no concrete share is stated; contribution for personal money/percentage; ratio for two sharing values including concatenated digits; whole when one person pays all or none of the cost, such as everything, komplett, just for me, or alleine.") var kind: Kind
}
@available(iOS 26.0, *) @Generable private struct LocalDateSource {
    var expenseNumber: Int
    @Guide(description: "Exact explicit date expression; do not copy monetary values or default dates.") var dateText: String
}
@available(iOS 26.0, *) @Generable private struct LocalDateSources {
    @Guide(description: "Only dates actually stated, one entry per affected purchase. Empty when no date is stated.", .count(0...10)) var updates: [LocalDateSource]
}
@available(iOS 26.0, *) @Generable private struct LocalShareSource {
    var expenseNumber: Int
    @Guide(description: "Exact explicitly stated contribution/ratio including person words; never a total purchase cost or default share.") var shareText: String
}
@available(iOS 26.0, *) @Generable private struct LocalShareSources {
    @Guide(description: "Only concrete personal contributions or ratios actually stated. Empty for missing/vague splits. Never invent default/equal actions.", .count(0...10)) var updates: [LocalShareSource]
}
@available(iOS 26.0, *) @Generable private struct LocalSourceEdit {
    @Guide(description: "Requested new title, or empty string if not renamed.") var title: String
    @Guide(description: "Exact quote of changed TOTAL price, or empty string if untouched. Exclude personal contributions.") var priceText: String
    @Guide(description: "Exact quote of changed date, or empty string if untouched.") var dateText: String
    @Guide(description: "Exact quote of changed personal contribution or ratio, or empty string if untouched.") var shareText: String
}
@available(iOS 26.0, *) @Generable private struct LocalDateKindPlan {
    @Generable enum Kind { case relative, weekday, calendar, unclear }
    var kind: Kind
}
@available(iOS 26.0, *) @Generable private struct LocalRemovalCheck {
    @Guide(description: "True only if the request asks to delete, remove, or cancel an expense (delete, remove, lösche, entferne, streiche). Paying, splitting, or changing details is not a deletion.")
    var deletionRequested: Bool
}
@available(iOS 26.0, *) @Generable private struct LocalWeekdayPlan {
    @Generable enum Weekday {
        case monday, tuesday, wednesday, thursday, friday, saturday, sunday
        /// Calendar weekday numbering (1 = Sunday).
        var calendarWeekday: Int {
            switch self {
            case .sunday: 1
            case .monday: 2
            case .tuesday: 3
            case .wednesday: 4
            case .thursday: 5
            case .friday: 6
            case .saturday: 7
            }
        }
    }
    @Generable enum Reference { case last, this, next, unclear }
    var weekday: Weekday
    @Guide(description: "last for an explicitly previous occurrence (last, letzten, vergangenen); next for an explicitly upcoming one (next, nächsten, kommenden); this for a plain or 'this' weekday; unclear for anything else, such as 'vorletzten' or 'the Friday before last'.")
    var reference: Reference
}
@available(iOS 26.0, *) @Generable private struct LocalOffsetPlan {
    @Guide(description: "Number of calendar days between today and the stated day, ignoring direction.", .range(0...36_600)) var distance: Int
    @Generable enum Direction { case past, today, future }
    var direction: Direction
}
@available(iOS 26.0, *) @Generable private struct LocalCalendarPlan { var year: Int; var month: Int; var day: Int }
@available(iOS 26.0, *) @Generable private struct LocalUnitPlan {
    @Generable enum Unit { case none, euros, percent, ratio }
    @Guide(description: "euros only for an explicitly currency-denominated contribution; percent for explicit percentages; ratio for two split numbers including speech-concatenated numbers; none if no concrete split.") var unit: Unit
    @Guide(description: "Exact currency word/symbol from the quoted split when unit euros; empty otherwise. Never infer a missing currency marker.") var unitEvidence: String
}
@available(iOS 26.0, *) @Generable private struct LocalRatioIntentPlan {
    @Generable enum Kind { case ratio, vague, unknown }
    var kind: Kind
}
@available(iOS 26.0, *) @Generable private struct LocalActorPlan {
    @Generable enum Actor { case unknown, speaker, partner }
    @Guide(description: "Explicitly named person associated with the QUOTED value in the source request. Never infer a person from number order.") var actor: Actor
}
@available(iOS 26.0, *) @Generable private struct LocalValuePlan { var value: Double }
@available(iOS 26.0, *) @Generable private struct LocalWholeSharePlan {
    @Generable enum PartnerPays { case all, nothing, unclear }
    @Guide(description: "How much the partner pays. all when the partner pays everything (my partner pays all of it, mein Partner zahlt komplett). nothing when the speaker keeps the whole cost (just for me, das zahle ich alleine, I pay everything, my partner owes nothing). unclear otherwise.") var partnerPays: PartnerPays
}
@available(iOS 26.0, *) @Generable private struct LocalRatioPlan {
    @Generable enum Format { case separateValues, concatenatedPercentages }
    @Guide(description: "concatenatedPercentages when speech produced ONE uninterrupted digit token encoding two percentage values; separateValues for two explicitly separate ratio numbers.") var format: Format
    @Guide(description: "Exact uninterrupted digit token for concatenatedPercentages, otherwise empty. Do not split or calculate it.") var digits: String
    @Guide(description: "First separately stated ratio number; zero for concatenatedPercentages.") var first: Double
    @Guide(description: "Second separately stated ratio number; zero for concatenatedPercentages.") var second: Double
}
@available(iOS 26.0, *) @Generable private struct LocalTitlePlan { var title: String }
@available(iOS 26.0, *) @Generable private struct LocalQuotePlan {
    @Guide(description: "Minimal exact substring satisfying the requested extraction. Exclude unrelated values/clauses. Empty if absent. Never copy the whole input unless it contains only the requested fragment.") var fragment: String
}


@available(iOS 26.0, *)
struct LocalTurnPlan {
    var actions: [LocalPlanAction]
}

@available(iOS 26.0, *)
enum LocalPlanDate {
    case notMentioned
    case relativeDays(Int)
    case calendarDate(year: Int, month: Int, day: Int)
    case unclear
}

@available(iOS 26.0, *)
struct LocalPlanShare {
    static var notMentioned: Self { .init(kind: .notMentioned, value: 0, secondValue: 0) }
    @Generable enum Kind { case notMentioned, partnerEuros, speakerEuros, unassignedEuros, partnerPercent, speakerPercent, unassignedRatio, unresolved }
    var kind: Kind
    var value: Double
    var secondValue: Double
    var intent: String? = nil
}

@available(iOS 26.0, *)
@Generable
struct LocalPlanMoney {
    @Guide(description: "Whole euro portion of the literal currency value. Zero when absent.", .range(0...999_999_999)) var euros: Int
    @Guide(description: "Cent portion of the literal currency value. Zero when no cents are stated.", .range(0...99)) var cents: Int
}

@available(iOS 26.0, *)
struct LocalPlanPurchase {
    var title: String
    var amount: LocalPlanMoney
    var date: LocalPlanDate
    var share: LocalPlanShare
}

@available(iOS 26.0, *)
struct LocalPlanEdit {
    var expenseNumber: Int
    var title: String?
    var amount: LocalPlanMoney?
    var date: LocalPlanDate
    var share: LocalPlanShare
}

@available(iOS 26.0, *)
enum LocalPlanAction {
    case add(LocalPlanPurchase)
    case edit(LocalPlanEdit)
    case remove(expenseNumber: Int)
}

/// The model understands language; the shared domain layer owns all draft changes.
/// A fresh bounded session includes relevant state and the outstanding question.
@available(iOS 26.0, *)
@MainActor
enum AppleExpenseInterpreter {
    struct Context: Decodable {
        struct Row: Decodable {
            let id: String
            let title: String
            let amount: Double?
            let date_iso: String?
            let split_mode: String?
            let split_value: Double?
            let missing_fields: [VoiceExpenseMissingField]?
            let split_intent: String?
            let pending_user_fixed_share: Double?

            var payload: VoiceExpenseDraftPayload {
                VoiceExpenseDraftPayload(id: id, title: title, amount: amount, dateISO: date_iso,
                    splitMode: split_mode, splitValue: split_value, confidence: 1,
                    missingFields: missing_fields ?? [], splitIntent: split_intent, pendingUserFixedShare: pending_user_fixed_share)
            }
        }
        let expenses: [Row]
        let clarification_question: String?
        let last_request: String?
    }

    /// Set for the one retry of a failed turn: greedy decoding repeats itself exactly,
    /// sampling lets the model take another path.
    @TaskLocal private static var isSampledRetry = false

    static func interpret(_ text: String, context: String?, trace: LocalVoiceTrace? = nil) async throws -> VoiceWorkspaceSyncPayload {
        try await LocalVoiceTraceScope.$current.withValue(trace) {
            do {
                return try await interpretTurn(text, context: context)
            } catch where isRetriable(error) {
                LocalVoiceTraceScope.current?.begin("sampledRetry")
                return try await $isSampledRetry.withValue(true) { try await interpretTurn(text, context: context) }
            }
        }
    }

    /// Model failures that another sampled attempt can avoid. Missing assets, language,
    /// context size, speech, and cancellation are not retried.
    private static func isRetriable(_ error: Error) -> Bool {
        guard !(error is CancellationError), !Task.isCancelled, let failure = error as? LocalVoiceFailure else { return false }
        switch failure.issue.category {
        case .guardrail, .refusal, .busy, .rateLimited, .schema, .invalidPlan, .timeout, .unknown: return true
        case .assets, .unavailable, .language, .context, .speech, .interrupted: return false
        }
    }

    private static var generationOptions: GenerationOptions {
        isSampledRetry ? GenerationOptions(samplingMode: .random(probabilityThreshold: 0.9), temperature: 0.7, maximumResponseTokens: 800)
                       : GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 800)
    }

    private static func interpretTurn(_ request: String, context: String?) async throws -> VoiceWorkspaceSyncPayload {
        guard LocalVoiceAvailability.current == .available else {
            throw LocalVoiceError(message: LocalVoiceAvailability.current.message)
        }
        // Prices are read and quoted from the normalized request; the user still sees their own words.
        let text = LocalTranscript.normalized(request)
        let today = VoiceModeViewModel.todayISOString()
        let timeZone = TimeZone.current
        let rows = try contextRows(context)
        let state = try context.map { try decodeContext($0) }
        let inventory = rows.enumerated().map { index, row in "\(index + 1): \(row.title) [needs \((row.missing_fields ?? []).map(\.rawValue).joined(separator: ","))]" }.joined(separator: "\n")
        var intent = LocalWorkspaceIntent(action: .add, expenseNumber: 0)
        if !rows.isEmpty {
            intent = try await generate(LocalWorkspaceIntent.self, quote: """
                Inventory: \(inventory)
                Pending question: \(state?.clarification_question ?? "")
                Previous request: \(state?.last_request ?? "")
                Latest request: \(text)
                """, instructions: """
                Classify the current expense request: add for a new purchase; totalPrice for its total purchase cost; share for a person's contribution/percentage/ratio; date for changing date; multiple for several changed fields; rename for changing title; remove for deletion; clarify for an unclear request. A person paying one euro is share, not totalPrice.
                Existing expenses are numbered. Return the ONE matching number for every edit/removal action. Zero only means unclear target or add.
                """)
            try Task.checkCancellation()
        }
        #if MODEL_EVALUATION
        print("PLAN ROUTE:", intent.action, intent.expenseNumber)
        #endif
        if intent.action == .remove {
            // Deleting is destructive; confirm it was asked for, otherwise treat it as an edit.
            let check = try await generate(LocalRemovalCheck.self, quote: text,
                instructions: "Decide only whether this request asks to delete an expense.")
            if !check.deletionRequested { intent.action = .multiple }
        }
        if intent.action != .add, !rows.indices.contains(intent.expenseNumber - 1) {
            return try VoiceWorkspaceDomain.apply([], to: rows.map(\.payload), understanding: request,
                question: loc("LocalAmbiguousCorrection"), todayISO: today, timeZone: timeZone)
        }
        let plan: LocalTurnPlan
        switch intent.action {
        case .add:
            let source = try await generate(LocalSourcePlan.self, quote: text, instructions: """
                Extract the new purchases in spoken order. Copy each total purchase price EXACTLY with original number words and currency; empty if absent. Dates and personal contributions are not purchases or total prices. Include partial purchases. Do not add old expenses or defaults.
                Reference date \(today), zone \(timeZone.identifier), locale \(LanguageManager.shared.activeLocale.identifier). Speaker is I/ich; partner is the other person; no names/order are known.
                """)
            let names = source.purchases.enumerated().map { "\($0.offset + 1): \($0.element.title)" }.joined(separator: "\n")
            var priceQuotes: [String] = []

            var shareContext = text
            for purchase in source.purchases {
                var price = purchaseQuote(purchase.priceText, in: text) ?? ""
                // A price spoken once backs one purchase; a second claim is re-selected.
                if !price.isEmpty && !isAvailable(price, in: text, taken: priceQuotes) { price = "" }
                if price.isEmpty && !purchase.priceText.isEmpty {
                    price = try await extractGroundedPrice(text, title: purchase.title, taken: priceQuotes)
                }
                priceQuotes.append(price)
                if !price.isEmpty, let range = numericBoundedRange(of: price, in: shareContext) {
                    shareContext.replaceSubrange(range, with: "[purchase total]")
                }
            }
            let hasDate = try await generate(LocalDatePresence.self, quote: text, instructions: "Decide only whether an explicit date expression occurs in the request. Relative days count. Prices never count. Do not compute a date.").hasDate
            let shareEvidence = try await generate(LocalSharePresence.self, quote: shareContext,
                instructions: "Extract only the requested split or personal contribution as an exact quote. Ignore purchase-total placeholders and dates. Classify the quote; absent/vague splitting has no concrete value. Never invent numbers or people.")
            let shareQuote = groundedQuote(shareEvidence.quote, in: shareContext).flatMap { groundedQuote($0, in: text) } ?? ""
            // A quote whose only number is a purchase price repeats that price, not a share.
            let shareTokens = VoiceWorkspaceDomain.literalNumericTokens(in: shareQuote)
            let hasResidualContribution = priceQuotes.allSatisfy { !$0.isEmpty } &&
                currencyEvidence(in: shareQuote) != nil && shareTokens.count == 1 &&
                !priceQuotes.contains { VoiceWorkspaceDomain.literalNumericTokens(in: $0) == shareTokens }
            let hasShare = shareEvidence.kind != .absent || hasLiteralRatioWitness(shareQuote) || hasResidualContribution
            let dated = hasDate ? try await generate(LocalDateSources.self, quote: "Purchase context: \(names)\nLATEST REQUEST: \(text)",
                instructions: LanguageManager.shared.activeLanguageCode == "de" ? "Kopiere ausschließlich ausdrücklich genannte Datumsformulierungen exakt, als zusammenhängendes Zitat mit originalen Zahlwörtern. Nicht umformulieren, nicht rechnen. Ordne jedes Zitat den betroffenen Kaufnummern zu; ein gemeinsames Datum gilt für alle genannten Käufe. Keine Preise oder Aufteilungen kopieren." : "Copy only explicit date expressions as exact continuous quotes with original number words. Do not paraphrase or calculate. Apply shared dates to every affected purchase number. Never copy monetary values or shares.") : LocalDateSources(updates: [])
            let shared: LocalShareSources
            if hasShare && source.purchases.count == 1 && !shareQuote.isEmpty {
                shared = .init(updates: [.init(expenseNumber: 1, shareText: shareQuote)])
            } else { shared = hasShare ? try await generate(LocalShareSources.self, quote: "Purchase context: \(names)\nLATEST REQUEST: \(text)",
                instructions: LanguageManager.shared.activeLanguageCode == "de" ? "Kopiere die ausdrücklich genannten persönlichen Anteile oder Aufteilungsverhältnisse wortgetreu als minimale zusammenhängende Zitate, inklusive zugehöriger Personenwörter. Originale Wortreihenfolge und Zahlwörter beibehalten. Ordne sie den Kaufnummern zu. Kaufpreise sind keine Anteile. Keine Standardwerte und keine Zuordnung aus Zahlenreihenfolge erfinden." : "Copy only concrete personal contributions/ratios as exact continuous source quotes including named persons. Keep original word order and number words. Associate by purchase number. Total costs are not contributions. No default shares or guessed people.") : LocalShareSources(updates: [])
            }
            guard dated.updates.allSatisfy({ source.purchases.indices.contains($0.expenseNumber - 1) }),
                  shared.updates.allSatisfy({ source.purchases.indices.contains($0.expenseNumber - 1) }) else {
                throw LocalVoiceFailure(issue: .init(.invalidPlan, reason: "source-target-out-of-range"))
            }
            guard Set(dated.updates.map(\.expenseNumber)).count == dated.updates.count,
                  Set(shared.updates.map(\.expenseNumber)).count == shared.updates.count else {
                throw LocalVoiceFailure(issue: .init(.invalidPlan, reason: "duplicate-source-field"))
            }
            var actions: [LocalPlanAction] = []
            var dateCache: [String: LocalPlanDate] = [:]
            for (index, purchase) in source.purchases.enumerated() {
                let priceQuote = priceQuotes[index]
                let dateSource = dated.updates.first(where: { $0.expenseNumber == index + 1 })
                let shareSource = shared.updates.first(where: { $0.expenseNumber == index + 1 })
                let dateQuote = try await repairQuote(dateSource?.dateText ?? "", in: text, field: "date", title: purchase.title, excluding: priceQuotes + shared.updates.map(\.shareText))
                var shareQuote = try await repairQuote(shareSource?.shareText ?? "", in: text, field: "concrete contribution or ratio", title: purchase.title, excluding: priceQuotes)
                // "Coffee for 4.50 euros" repeats a purchase price; it is not a share.
                let repeatsPrice = !shareQuote.isEmpty && priceQuotes.contains { price in
                    !price.isEmpty && (shareQuote.range(of: price, options: .caseInsensitive) != nil ||
                        VoiceWorkspaceDomain.literalNumericTokens(in: shareQuote) == VoiceWorkspaceDomain.literalNumericTokens(in: price)
                            && !VoiceWorkspaceDomain.literalNumericTokens(in: price).isEmpty)
                }
                if repeatsPrice { shareQuote = "" }
                let amount = try await interpretMoney(priceQuote)
                let date: LocalPlanDate
                if dateQuote.isEmpty && (dateSource != nil || (hasDate && dated.updates.isEmpty)) { date = .unclear }
                else if let cached = dateCache[dateQuote] { date = cached }
                else { date = try await interpretDate(dateQuote, today: today, timeZone: timeZone); dateCache[dateQuote] = date }
                let share: LocalPlanShare
                if repeatsPrice {
                    share = .notMentioned
                } else if shareQuote.isEmpty && (shareSource != nil || (hasShare && shared.updates.isEmpty)) {
                    share = .init(kind: .unresolved, value: 0, secondValue: 0, intent: shareSource?.shareText ?? text)
                } else { share = try await interpretShare(shareQuote, context: text, recognizedIntent: hasShare,
                                                          recognizedRatio: shareEvidence.kind == .ratio, recognizedWhole: shareEvidence.kind == .whole) }
                actions.append(.add(.init(title: purchase.title, amount: amount, date: date, share: share)))
            }
            plan = .init(actions: actions)
        case .remove: plan = .init(actions: [.remove(expenseNumber: intent.expenseNumber)])
        case .clarify: plan = .init(actions: [])
        case .totalPrice:
            let amount = try await interpretMoney(text)
            plan = .init(actions: [.edit(.init(expenseNumber: intent.expenseNumber, title: nil, amount: amount, date: .notMentioned, share: .notMentioned))])
        case .date:
            let date = try await interpretDate(text, today: today, timeZone: timeZone)
            plan = .init(actions: [.edit(.init(expenseNumber: intent.expenseNumber, title: nil, amount: nil, date: date, share: .notMentioned))])
        case .share:
            let share = try await interpretShare(text, context: text)
            plan = .init(actions: [.edit(.init(expenseNumber: intent.expenseNumber, title: nil, amount: nil, date: .notMentioned, share: share))])
        case .rename:
            let title = try await generate(LocalTitlePlan.self, quote: text, instructions: "Extract only the explicitly requested new purchase title.").title
            plan = .init(actions: [.edit(.init(expenseNumber: intent.expenseNumber, title: title, amount: nil, date: .notMentioned, share: .notMentioned))])
        case .multiple:
            let source = try await generate(LocalSourceEdit.self, quote: text, instructions: "Extract only explicitly CHANGED fields. Copy price/date/share quotes exactly. Empty means unchanged; personal contributions are not total prices. Do not copy existing values.")
            let priceQuote = try await repairQuote(source.priceText, in: text, field: "changed total price", title: rows[intent.expenseNumber - 1].title)
            let dateQuote = try await repairQuote(source.dateText, in: text, field: "changed date", title: rows[intent.expenseNumber - 1].title)
            let shareQuote = try await repairQuote(source.shareText, in: text, field: "changed contribution or ratio", title: rows[intent.expenseNumber - 1].title)
            let amount = priceQuote.isEmpty ? nil : try await interpretMoney(priceQuote)
            let date = try await interpretDate(dateQuote, today: today, timeZone: timeZone)
            let share = try await interpretShare(shareQuote, context: text)
            plan = .init(actions: [.edit(.init(expenseNumber: intent.expenseNumber, title: source.title.isEmpty ? nil : source.title, amount: amount, date: date, share: share))])
        }
        try Task.checkCancellation()
        #if MODEL_EVALUATION
        print("APP PLAN:", plan)
        #endif
        LocalVoiceTraceScope.current?.begin("validatePlan")
        let result = try applyPlan(plan, to: rows.map(\.payload), transcript: request, today: today, timeZone: timeZone)
        LocalVoiceTraceScope.current?.endStep()
        return result
    }

    private static func generate<T: Generable>(_ type: T.Type, quote: String, instructions: String) async throws -> T {
        try Task.checkCancellation()
        let trace = LocalVoiceTraceScope.current
        trace?.begin(String(describing: type))
        do {
            let locale = LanguageManager.shared.activeLanguageCode == "de" ? "de_DE" : "en_US"
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: "The person's locale is \(locale).\n\(instructions)")
            let response = try await session.respond(to: quote, generating: type, options: generationOptions)
            try Task.checkCancellation()
            trace?.endStep()
            #if MODEL_EVALUATION
            print("RAW", String(describing: type), "INPUT:", quote, "OUTPUT:", response.content.generatedContent.jsonString)
            #endif
            return response.content
        } catch {
            try Task.checkCancellation()
            let issue = LocalVoiceIssue.classify(error)
            trace?.record(issue)
            throw LocalVoiceFailure(issue: issue)
        }
    }

    private static func groundedQuote(_ quote: String, in text: String) -> String? {
        let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, text.range(of: trimmed, options: .caseInsensitive) != nil else { return nil }
        return trimmed
    }

    private static func repairQuote(_ quote: String, in text: String, field: String, title: String, excluding: [String] = []) async throws -> String {
        if quote.isEmpty { return "" }
        if let grounded = groundedQuote(quote, in: text) { return grounded }
        if field.contains("date") || field.contains("contribution") {
            var isolated = text
            for fragment in excluding where !fragment.isEmpty {
                isolated = isolated.replacingOccurrences(of: fragment, with: "[other field]", options: .caseInsensitive)
            }
            let instruction: String
            if field.contains("contribution") {
                instruction = LanguageManager.shared.activeLanguageCode == "de"
                    ? "Kopiere ausschließlich den persönlichen Anteil oder das Aufteilungsverhältnis wortgetreu aus dem Text, einschließlich der zugehörigen Personenwörter. Minimales zusammenhängendes Zitat mit originaler Wortreihenfolge und Zahlwörtern. Platzhalter sind keine Anteile. Nicht rechnen. Falls kein Anteil genannt ist, leere Zeichenfolge."
                    : "Copy only the minimal exact continuous personal contribution/ratio quote, including associated person words. Preserve word order and number words. Placeholders are not contributions. No calculation. Empty if absent."
            } else { instruction = LanguageManager.shared.activeLanguageCode == "de"
                ? "Kopiere ausschließlich die Datumsformulierung wortgetreu aus dem Text. Minimales zusammenhängendes Zitat, originale Zahlwörter. Nicht umformulieren oder rechnen. Platzhalter sind keine Datumsangaben. Wenn kein Datum enthalten ist, leere Zeichenfolge."
                : "Copy only the minimal exact continuous date phrase from this text. Keep original number words. Never paraphrase or calculate. Placeholders are not dates. Empty if absent."
            }
            let repaired = try await generate(LocalQuotePlan.self, quote: isolated, instructions: instruction).fragment
            if let grounded = groundedQuote(repaired, in: isolated), groundedQuote(grounded, in: text) != nil { return grounded }
        }
        LocalVoiceTraceScope.current?.record(.init(.invalidPlan, reason: field.contains("date") ? "unverified-date-source" : field.contains("contribution") ? "unverified-share-source" : "unverified-price-source"))
        return ""
    }

    private static func extractGroundedPrice(_ text: String, title: String, taken: [String] = []) async throws -> String {
        // Runtime guided choices contain only actual numeric/currency source spans.
        // The model associates a purchase with a quote; it cannot rewrite the number.
        let candidates = Array(Set(VoiceWorkspaceDomain.literalNumericTokens(in: text)
            .compactMap { purchaseQuote($0, in: text) })).filter { isAvailable($0, in: text, taken: taken) }
            .sorted { (numericBoundedRange(of: $0, in: text)?.lowerBound ?? text.endIndex) < (numericBoundedRange(of: $1, in: text)?.lowerBound ?? text.endIndex) }
        if !candidates.isEmpty && candidates.count <= 32 {
            let trace = LocalVoiceTraceScope.current
            trace?.begin("LocalGroundedPrice")
            do {
                let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "GroundedPrice", properties: [
                    .init(name: "quote", description: "Select the TOTAL purchase price for the named purchase, never a personal contribution. Empty if absent.",
                          schema: DynamicGenerationSchema(name: "PriceQuote", anyOf: [""] + candidates))
                ]), dependencies: [])
                let locale = LanguageManager.shared.activeLanguageCode == "de" ? "de_DE" : "en_US"
                let session = LanguageModelSession(model: SystemLanguageModel.default,
                    instructions: "The person's locale is \(locale). Select only the source price belonging to the named purchase. Do not calculate or invent values.")
                let response = try await session.respond(to: "Purchase: \(title)\nRequest: \(text)", schema: schema,
                    options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 100))
                try Task.checkCancellation()
                let quote = try response.content.value(String.self, forProperty: "quote")
                trace?.endStep()
                guard candidates.contains(quote) || quote.isEmpty else { throw invalidOutput }
                #if MODEL_EVALUATION
                print("RAW LocalGroundedPrice INPUT:", text, "PURCHASE:", title, "OUTPUT:", quote)
                #endif
                return quote
            } catch {
                try Task.checkCancellation()
                let issue = LocalVoiceIssue.classify(error)
                trace?.record(issue)
                throw LocalVoiceFailure(issue: issue)
            }
        }
        let source = try await extractMoneySource(text, title: title)
        return validatedMoneyQuote(source, in: text).flatMap { isAvailable($0, in: text, taken: taken) ? $0 : nil } ?? ""
    }

    /// Whether a price quote is spoken more often than earlier purchases already used it.
    static func isAvailable(_ quote: String, in text: String, taken: [String]) -> Bool {
        var spoken = 0
        var remaining = text
        while let range = numericBoundedRange(of: quote, in: remaining) {
            spoken += 1
            remaining = String(remaining[range.upperBound...])
        }
        return taken.filter { $0.caseInsensitiveCompare(quote) == .orderedSame }.count < spoken
    }

    private static func extractMoneySource(_ text: String, title: String) async throws -> LocalMoneySource {
        let instructions = LanguageManager.shared.activeLanguageCode == "de"
            ? "Extrahiere ausschließlich den gesamten Kaufpreis für \(title), nicht den persönlichen Anteil oder die Aufteilung. Kopiere das minimale zusammenhängende Preiszitat samt Währung exakt aus der Anfrage. Zahlwörter unverändert. Eine Aufteilungszahl ist kein Preis. Fehlende Angaben bleiben leer. Nicht rechnen."
            : "Extract only the total purchase price for \(title), excluding personal contributions and sharing ratios. Copy the minimal exact continuous price quotation with its currency. Preserve number words. Missing fields are empty. Do not calculate."
        return try await generate(LocalMoneySource.self, quote: text, instructions: instructions)
    }

    static func validatedMoneyQuote(_ source: LocalMoneySource, in text: String) -> String? {
        guard let quote = purchaseQuote(source.priceText, in: text),
              isCurrencyEvidence(source.currencyText, in: quote) else {
            LocalVoiceTraceScope.current?.record(.init(.invalidPlan, reason: "unverified-price-currency")); return nil
        }
        return quote
    }

    /// The first occurrence of `quote` that does not begin or end inside another numeric
    /// token. "2,50 €" must skip the copy embedded in "12,50 €" and match a later one.
    static func numericBoundedRange(of quote: String, in source: String) -> Range<String.Index>? {
        let numericBoundary: (Character) -> Bool = { $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }
        let checksLeft = quote.first.map(numericBoundary) ?? false
        let checksRight = quote.last.map(numericBoundary) ?? false
        var remaining = source.startIndex..<source.endIndex
        while !quote.isEmpty, let range = source.range(of: quote, options: .caseInsensitive, range: remaining) {
            let left = !checksLeft || range.lowerBound == source.startIndex || !numericBoundary(source[source.index(before: range.lowerBound)])
            let right = !checksRight || range.upperBound == source.endIndex || !numericBoundary(source[range.upperBound])
            if left && right { return range }
            remaining = source.index(after: range.lowerBound)..<source.endIndex
        }
        return nil
    }

    static func purchaseQuote(_ fragment: String, in source: String) -> String? {
        guard let quote = groundedQuote(fragment, in: source),
              let range = numericBoundedRange(of: quote, in: source) else { return nil }
        if currencyEvidence(in: quote) != nil { return quote }
        // Join only adjacent literal currency bytes, never a distant unit or invented text.
        var next = range.upperBound
        while next < source.endIndex && source[next].isWhitespace { next = source.index(after: next) }
        for unit in ["€", "euros", "euro", "eur"] {
            if let match = source.range(of: unit, options: [.caseInsensitive, .anchored], range: next..<source.endIndex),
               match.upperBound == source.endIndex || !source[match.upperBound].isLetter {
                return String(source[range.lowerBound..<match.upperBound])
            }
        }
        return nil
    }

    static func hasLiteralRatioWitness(_ quote: String) -> Bool {
        guard currencyEvidence(in: quote) == nil, !quote.contains("%") else { return false }
        let tokens = VoiceWorkspaceDomain.literalNumericTokens(in: quote)
        if tokens.count == 1 { return VoiceWorkspaceDomain.concatenatedPercentages(tokens[0]) != nil }
        return tokens.count == 2 && tokens.allSatisfy { token in
            guard let value = Double(token.replacingOccurrences(of: ",", with: ".")) else { return false }
            return value >= 0 && value <= 100
        }
    }

    static func literalMoney(_ token: String,
                             groupingSeparator: Character = LanguageManager.shared.activeLanguageCode == "de" ? "." : ",") -> LocalPlanMoney? {
        guard !token.isEmpty, token.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }
        let decimal: String
        if let ungrouped = ungroupedMoney(token, groupingSeparator: groupingSeparator) {
            decimal = ungrouped
        } else {
            let pieces = token.split(whereSeparator: { $0 == "." || $0 == "," })
            guard pieces.count <= 2, pieces.count == 1 || (1...2).contains(pieces[1].count),
                  token.filter({ $0 == "." || $0 == "," }).count == pieces.count - 1 else { return nil }
            decimal = token.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(decimal), value > 0, value <= ExpenseValidation.maximumAmount else { return nil }
        let cents = Int((value * 100).rounded())
        return .init(euros: cents / 100, cents: cents % 100)
    }

    /// Thousands groups in the app language's own convention ("1.500", "2.500,00" in German;
    /// "1,250", "1,250.00" in English): exactly three digits per group and an optional
    /// two-digit decimal part. Other groupings stay unverified rather than becoming decimals.
    private static func ungroupedMoney(_ token: String, groupingSeparator: Character) -> String? {
        let decimalSeparator: Character = groupingSeparator == "." ? "," : "."
        var integerPart = Substring(token)
        var fraction = ""
        if let decimalIndex = token.lastIndex(of: decimalSeparator) {
            integerPart = token[..<decimalIndex]
            fraction = String(token[token.index(after: decimalIndex)...])
            guard (1...2).contains(fraction.count), fraction.allSatisfy(\.isNumber) else { return nil }
        }
        let groups = integerPart.split(separator: groupingSeparator, omittingEmptySubsequences: false)
        guard groups.count >= 2, (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }),
              groups.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return groups.joined() + (fraction.isEmpty ? "" : "." + fraction)
    }

    private static func currencyEvidence(in quote: String) -> String? {
        // Closed literal EUR witness validation, not a spoken-number parser.
        for token in ["€", "euros", "euro", "eur"] {
            var remainder = quote.startIndex..<quote.endIndex
            while let range = quote.range(of: token, options: .caseInsensitive, range: remainder) {
                let left = range.lowerBound == quote.startIndex || !quote[quote.index(before: range.lowerBound)].isLetter
                let right = range.upperBound == quote.endIndex || !quote[range.upperBound].isLetter
                if token == "€" || (left && right) { return String(quote[range]) }
                guard range.upperBound < quote.endIndex else { break }
                remainder = range.upperBound..<quote.endIndex
            }
        }
        return nil
    }

    private static func isCurrencyEvidence(_ token: String, in quote: String) -> Bool {
        ["€", "eur", "euro", "euros"].contains(token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) && groundedQuote(token, in: quote) != nil
    }

    private static func interpretMoney(_ quote: String) async throws -> LocalPlanMoney {
        if quote.isEmpty { return .init(euros: 0, cents: 0) }
        if quote.contains(where: { $0.isASCII && $0.isNumber }) {
            let tokens = VoiceWorkspaceDomain.literalNumericTokens(in: quote)
            guard tokens.count == 1, let money = literalMoney(tokens[0]) else {
                LocalVoiceTraceScope.current?.record(.init(.invalidPlan, reason: "unverified-money-number"))
                return .init(euros: 0, cents: 0)
            }
            return money
        }
        return try await generate(LocalPlanMoney.self, quote: quote,
            instructions: "Extract the literal currency amount into whole euros and cents. In a correction extract the new value. Missing value is zero euros and cents.")
    }

    private static func interpretDate(_ quote: String, today: String, timeZone: TimeZone) async throws -> LocalPlanDate {
        if quote.isEmpty { return .notMentioned }
        let kind = try await generate(LocalDateKindPlan.self, quote: quote,
            instructions: "Classify this date expression: weekday when it names a day of the week (Friday, letzten Montag, am Sonntag); relative for other days relative to now (yesterday, vorgestern, three days ago); calendar for a named calendar day/month/year; unclear when it cannot be understood. Do not calculate any date.").kind
        switch kind {
        case .weekday:
            // The model only names the weekday; the app computes the date from today's.
            let plan = try await generate(LocalWeekdayPlan.self, quote: quote,
                instructions: "Identify the named day of the week and which occurrence is meant. Do not calculate a date.")
            let reference: VoiceWorkspaceDomain.WeekdayReference
            switch plan.reference {
            case .last: reference = .last
            case .this: reference = .this
            case .next: reference = .next
            case .unclear: return .unclear
            }
            guard let days = VoiceWorkspaceDomain.weekdayOffset(plan.weekday.calendarWeekday, reference: reference,
                                                                 todayISO: today, timeZone: timeZone) else { return .unclear }
            return .relativeDays(days)
        case .relative:
            let offset = try await generate(LocalOffsetPlan.self, quote: quote,
                instructions: LanguageManager.shared.activeLanguageCode == "de"
                    ? "Bestimme getrennt den Abstand in ganzen Kalendertagen und die Zeitrichtung des genannten Tages relativ zu heute. Vergangene Tage haben die Richtung past, kommende future, heute today. Keine absoluten Datumsberechnungen."
                    : "Extract separately the distance in whole calendar days and its direction relative to today. Past days are past; upcoming days future; today today. Do not calculate an absolute date.")
            if offset.direction == .today && offset.distance != 0 { return .unclear }
            return .relativeDays(offset.direction == .past ? -offset.distance : offset.direction == .future ? offset.distance : 0)
        case .calendar:
            let date = try await generate(LocalCalendarPlan.self, quote: quote,
                instructions: "Copy the literal calendar year, month and day. Missing year uses the year of reference date \(today). Keep impossible days unchanged for app validation. Gregorian calendar, zone \(timeZone.identifier). Do not reinterpret it as a relative offset.")
            return .calendarDate(year: date.year, month: date.month, day: date.day)
        case .unclear: return .unclear
        }
    }

    /// "Everything", "nothing", or "just for me": the model decides whether the partner pays
    /// all of the cost or none of it; the app sets the partner's percentage. Unclear is nil.
    private static func wholeShare(_ quote: String, context: String) async throws -> LocalPlanShare? {
        let pays = try await generate(LocalWholeSharePlan.self, quote: "SOURCE REQUEST: \(context)\nQUOTED SPLIT: \(quote)",
            instructions: "Decide whether the partner pays all of this cost or none of it. Speaker is I/ich/me; partner the other person. Do not calculate.").partnerPays
        switch pays {
        case .all: return .init(kind: .partnerPercent, value: 100, secondValue: 0)
        case .nothing: return .init(kind: .partnerPercent, value: 0, secondValue: 0)
        case .unclear: return nil
        }
    }

    /// An unverifiable contribution stays open; it must never become a saveable €0 share.
    static func euroShare(_ value: Double?, kind: LocalPlanShare.Kind, quote: String) -> LocalPlanShare {
        guard let value else { return .init(kind: .unresolved, value: 0, secondValue: 0, intent: quote) }
        return .init(kind: kind, value: value, secondValue: 0)
    }

    static func unresolvedShare(_ quote: String, recognizedIntent: Bool) -> LocalPlanShare {
        recognizedIntent ? .init(kind: .unresolved, value: 0, secondValue: 0, intent: quote) : .notMentioned
    }

    private static func interpretShare(_ quote: String, context: String, recognizedIntent: Bool = false,
                                       recognizedRatio: Bool = false, recognizedWhole: Bool = false) async throws -> LocalPlanShare {
        if quote.isEmpty { return .notMentioned }
        do {
            if recognizedWhole, let whole = try await wholeShare(quote, context: context) { return whole }
            let descriptor = try await generate(LocalUnitPlan.self, quote: quote, instructions: "Extract only the literal unit of the QUOTED split. Currency requires an explicit currency unit. Numeric ratios, including concatenated ratio numbers from speech, are ratio. Total prices or vague sharing with no concrete split are none. Do not infer a unit from defaults.")
            var unit = descriptor.unit
            // "My partner pays all of it" has no number but is a concrete share.
            if unit == .none, !recognizedRatio, !recognizedWhole, let whole = try await wholeShare(quote, context: context) { return whole }
            if recognizedRatio && unit == .none { unit = .ratio }
            if unit == .euros {
                // Validate a model-supplied closed EUR unit token, not spoken-value language.
                let token = descriptor.unitEvidence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let supported = ["€", "eur", "euro", "euros"].contains(token) && groundedQuote(descriptor.unitEvidence, in: quote) != nil
                if !supported {
                    let intent = try await generate(LocalRatioIntentPlan.self, quote: quote, instructions: "Identify a concrete numeric split ratio, including concatenated speech transcription. Vague splitting with no different concrete intent is vague. Other unsupported expressions are unknown. Do not invent currency or people.").kind
                    switch intent {
                    case .ratio: unit = .ratio
                    case .vague: return recognizedIntent ? .init(kind: .unresolved, value: 0, secondValue: 0, intent: quote) : .notMentioned
                    case .unknown: return .init(kind: .unresolved, value: 0, secondValue: 0, intent: quote)
                    }
                }
            }
            if unit == .none && recognizedIntent {
                let intent = try await generate(LocalRatioIntentPlan.self, quote: quote,
                    instructions: "A concrete split was already recognized. Identify whether this source expresses a numeric ratio. Do not erase the recognized split if uncertain.").kind
                if intent == .ratio { unit = .ratio }
                else { return unresolvedShare(quote, recognizedIntent: true) }
            }
            if unit == .none { return .notMentioned }
            if unit == .ratio {
                let literal = VoiceWorkspaceDomain.literalNumericTokens(in: quote)
                if !literal.isEmpty {
                    if literal.count == 1, let pair = VoiceWorkspaceDomain.concatenatedPercentages(literal[0]) {
                        return .init(kind: .unassignedRatio, value: pair.0, secondValue: pair.1)
                    }
                    if literal.count == 2, let first = Double(literal[0].replacingOccurrences(of: ",", with: ".")),
                       let second = Double(literal[1].replacingOccurrences(of: ",", with: ".")) {
                        return .init(kind: .unassignedRatio, value: first, secondValue: second)
                    }
                    return .init(kind: .unresolved, value: 0, secondValue: 0, intent: quote)
                }
                let ratio = try await generate(LocalRatioPlan.self, quote: quote,
                    instructions: "Extract the two separately stated ratio values written as words. Do not assign people or compute shares.")
                return .init(kind: .unassignedRatio, value: ratio.first, secondValue: ratio.second)
            }
            let input = "SOURCE REQUEST: \(context)\nQUOTED SPLIT: \(quote)"
            let actor = try await generate(LocalActorPlan.self, quote: input, instructions: "Identify only the person explicitly associated with the quoted split value. Speaker is I/ich, partner the other person. Unknown if no explicit association. Do not infer person ordering.").actor
            let valueInstruction = LanguageManager.shared.activeLanguageCode == "de"
                ? "Kopiere aus diesem Anteil wortgetreu nur den genannten \(unit == .euros ? "Eurobetrag" : "Prozentwert") für die Person \(actor). Behalte Zahlwörter und originale Wortreihenfolge bei. Nicht rechnen, keine neuen Wörter. Falls unbekannt, leere Zeichenfolge."
                : "Copy only the exact literal \(unit == .euros ? "currency amount" : "percentage") substring for actor \(actor) from this quoted split. Preserve number words. Do not calculate, invent text, or include another person's value. Empty if unknown."
            let valueText = try await generate(LocalQuotePlan.self, quote: quote, instructions: valueInstruction).fragment
            guard let grounded = groundedQuote(valueText, in: quote) else {
                return .init(kind: .unresolved, value: 0, secondValue: 0, intent: quote)
            }
            if unit == .euros {
                let kind: LocalPlanShare.Kind = actor == .partner ? .partnerEuros : actor == .speaker ? .speakerEuros : .unassignedEuros
                return euroShare(try normalizedMoney(await interpretMoney(grounded)), kind: kind, quote: quote)
            }
            var value: Double
            let literalPercent = VoiceWorkspaceDomain.literalNumericTokens(in: grounded)
            if literalPercent.count == 1, let literal = Double(literalPercent[0].replacingOccurrences(of: ",", with: ".")) {
                value = literal
            } else {
                value = try await generate(LocalValuePlan.self, quote: grounded, instructions: "Copy this literal percentage as a number. Do not calculate the complementary percentage.").value
                // Spoken fractions such as "a quarter" or "die Hälfte" can arrive as 0.25 or 0.5.
                if value > 0 && value <= 1 { value *= 100 }
            }
            return .init(kind: actor == .speaker ? .speakerPercent : actor == .partner ? .partnerPercent : .unassignedRatio,
                value: value, secondValue: actor == .unknown ? 100 - value : 0)
        } catch {
            try Task.checkCancellation()
            // A blocked/failed field must not discard recognized prices/dates or
            // manufacture a default for a recognized concrete contribution.
            return .init(kind: .unresolved, value: 0, secondValue: 0, intent: quote)
        }
    }

    static func applyPlan(_ plan: LocalTurnPlan, to rows: [VoiceExpenseDraftPayload], transcript: String,
                          today: String, timeZone: TimeZone) throws -> VoiceWorkspaceSyncPayload {
        let changes: [VoiceExpenseChange] = try plan.actions.map { action in
            var change: VoiceExpenseChange
            switch action {
            case .add(let purchase):
                change = .init(existingID: nil, remove: false, title: purchase.title,
                    amount: try normalizedMoney(purchase.amount).map { .value($0) } ?? .uncertain)
                change.date = domainDate(purchase.date)
                change.share = domainShare(purchase.share, total: try normalizedMoney(purchase.amount))
            case .edit(let edit):
                guard rows.indices.contains(edit.expenseNumber - 1) else { throw invalidOutput }
                change = .init(existingID: rows[edit.expenseNumber - 1].id, remove: false, title: edit.title,
                    amount: try edit.amount.map { try normalizedMoney($0).map { .value($0) } ?? .unresolved } ?? .unchanged)
                change.date = domainDate(edit.date)
                change.share = domainShare(edit.share, total: try edit.amount.flatMap { try normalizedMoney($0) } ?? rows[edit.expenseNumber - 1].amount)
            case .remove(let number):
                guard rows.indices.contains(number - 1) else { throw invalidOutput }
                change = .init(existingID: rows[number - 1].id, remove: true)
            }
            return change
        }
        return try VoiceWorkspaceDomain.apply(changes, to: rows, understanding: transcript,
            question: changes.isEmpty ? loc("LocalAmbiguousCorrection") : "", todayISO: today, timeZone: timeZone)
    }

    private static func normalizedMoney(_ amount: LocalPlanMoney) throws -> Double? {
        guard amount.euros >= 0, amount.euros <= 999_999_999, (0...99).contains(amount.cents) else { throw invalidOutput }
        if amount.euros == 0 && amount.cents == 0 { return nil }
        return (Double(amount.euros) + Double(amount.cents) / 100).roundedMoney
    }

    private static func domainDate(_ date: LocalPlanDate?) -> VoiceExpenseChange.DateValue {
        guard let date else { return .unchanged }
        switch date {
        case .notMentioned: return .unchanged
        case .relativeDays(let days): return .relativeDays(days)
        case .calendarDate(let year, let month, let day): return .absolute(String(format: "%04d-%02d-%02d", year, month, day))
        case .unclear: return .uncertain
        }
    }

    private static func domainShare(_ share: LocalPlanShare?, total: Double? = nil) -> VoiceExpenseChange.Share {
        guard let share else { return .unchanged }
        let valid: Bool
        switch share.kind {
        case .notMentioned, .unresolved: valid = true
        case .partnerPercent, .speakerPercent: valid = share.value.isFinite && (0...100).contains(share.value)
        case .partnerEuros, .unassignedEuros: valid = share.value.isFinite && (0...ExpenseValidation.maximumAmount).contains(share.value)
        case .speakerEuros: valid = share.value.isFinite && (0...ExpenseValidation.maximumAmount).contains(share.value) && (total.map { share.value <= $0 } ?? true)
        case .unassignedRatio: valid = share.value.isFinite && share.secondValue.isFinite && share.value >= 0 && share.secondValue >= 0 && (share.value + share.secondValue).isFinite && share.value + share.secondValue > 0
        }
        guard valid else { return .unresolved(share.intent ?? loc("VoiceCheckSplit")) }
        switch share.kind {
        case .notMentioned: return .unchanged
        case .partnerEuros: return .partnerFixed(share.value)
        case .speakerEuros: return .userFixed(share.value)
        case .unassignedEuros: return .unassignedFixed(share.value)
        case .partnerPercent: return .partnerPercent(share.value)
        case .speakerPercent: return .userPercent(share.value)
        case .unassignedRatio: return .unassignedRatio(share.value, share.secondValue)
        case .unresolved: return .unresolved(share.intent ?? loc("VoiceCheckSplit"))
        }
    }

    private static func decodeContext(_ context: String) throws -> Context {
        guard let start = context.firstIndex(of: "{") else { throw invalidOutput }
        return try JSONDecoder().decode(Context.self, from: Data(context[start...].utf8))
    }

    private static func contextRows(_ context: String?) throws -> [Context.Row] {
        guard let context, let start = context.firstIndex(of: "{") else { return [] }
        return try decodeContext(String(context[start...])).expenses
    }

    static func payload(_ output: LocalExpenseInterpretation, transcript: String, context: String?,
                        today: String = VoiceModeViewModel.todayISOString(), timeZone: TimeZone = .current) throws -> VoiceWorkspaceSyncPayload {
        let rows = try contextRows(context)
        var changes: [VoiceExpenseChange] = []
        for update in output.updates {
            let id: String?
            switch update.action {
            case .add:
                guard update.expenseNumber == 0 else { throw invalidOutput }
                id = nil
            case .correct, .remove, .rename:
                guard rows.indices.contains(update.expenseNumber - 1) else { throw invalidOutput }
                id = rows[update.expenseNumber - 1].id
            }
            var change = VoiceExpenseChange(existingID: id, remove: update.action == .remove, title: update.title)
            if change.remove { changes.append(change); continue }
            if let amount = update.amount { change.amount = .value(amount) }
            else if update.amountUnclear { change.amount = .uncertain }
            if update.dateUnclear { change.date = .uncertain }
            else if let offset = update.dayOffset { change.date = .relativeDays(offset) }
            else if let iso = update.dateISO { change.date = .absolute(iso) }
            switch update.shareKind {
            case .unchanged, .notMentioned: break
            case .uncertain: change.share = .equalDefault
            case .partnerPercent, .userPercent, .partnerFixed, .userFixed, .unassignedRatio:
                guard let value = update.shareValue else { throw invalidOutput }
                switch update.shareKind {
                case .partnerPercent: change.share = .partnerPercent(value)
                case .userPercent: change.share = .userPercent(value)
                case .partnerFixed: change.share = .partnerFixed(value)
                case .userFixed: change.share = .userFixed(value)
                case .unassignedRatio:
                    guard let second = update.secondShareValue else { throw invalidOutput }
                    change.share = .unassignedRatio(value, second)
                default: break
                }
            }
            changes.append(change)
        }
        var result = try VoiceWorkspaceDomain.apply(changes, to: rows.map(\.payload),
            understanding: transcript, question: output.clarificationQuestion, todayISO: today, timeZone: timeZone)
        if !changes.isEmpty, result.expenses.allSatisfy({ $0.draft.isReadyForSaving }) {
            result = VoiceWorkspaceSyncPayload(userUnderstanding: transcript, clarificationQuestion: "",
                expenses: result.expenses, changedExpenseIDs: result.changedExpenseIDs, removedExpenseIDs: result.removedExpenseIDs)
        }
        return result
    }

    private static var invalidOutput: LocalVoiceFailure { LocalVoiceFailure(issue: .init(.invalidPlan, reason: "invalid-value-or-target")) }
}
