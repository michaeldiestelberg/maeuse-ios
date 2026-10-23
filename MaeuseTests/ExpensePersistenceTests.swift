import CoreTransferable
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Maeuse

@MainActor
final class ExpensePersistenceTests: XCTestCase {
    private func container(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Expense.self])
        let config = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testManualCreateEditDeleteAndMonthTotals() throws {
        let store = try container()
        let context = store.mainContext
        let editor = ExpenseEditorViewModel()
        editor.prepareForNew()
        editor.amountText = "48,60"
        editor.description = "Groceries"
        editor.date = try XCTUnwrap(Expense.dateFromISO("2026-09-15"))
        editor.setPartnerFraction(0.4)
        try editor.save(context: context)
        let expense = try XCTUnwrap(context.fetch(FetchDescriptor<Expense>()).first)
        XCTAssertEqual(expense.amount, 48.60)
        XCTAssertEqual(expense.partnerShare, 19.44)
        XCTAssertFalse(editor.isPresented)

        editor.prepareForEdit(expense)
        editor.amountText = "60.00"
        editor.description = "Corrected groceries"
        try editor.save(context: context)
        let list = ExpenseListViewModel()
        list.currentYear = 2026
        list.currentMonth = 9
        let rows = list.filteredExpenses(from: try context.fetch(FetchDescriptor<Expense>()))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(list.totalAmount(for: rows), 60)
        XCTAssertEqual(list.partnerTotal(for: rows), 24)
        list.nextMonth()
        XCTAssertTrue(list.filteredExpenses(from: rows).isEmpty)
        list.previousMonth()
        XCTAssertEqual(list.filteredExpenses(from: rows).count, 1)

        editor.prepareForEdit(expense)
        try editor.delete(context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
    }

    func testRestoreReplacesExistingIDsAndSurvivesStoreReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.store")
        let date = try XCTUnwrap(Expense.dateFromISO("2026-09-14"))
        let original = Expense(id: "stable-id", amount: 18.90, desc: "Pharmacy", date: date,
                               splitMode: .fixed, splitValue: 10, createdAt: date)
        let backup = try BackupService.exportBackup(expenses: [original])
        do {
            let store = try container(at: url)
            let context = store.mainContext
            context.insert(original)
            try context.save()
            original.amount = 99
            context.insert(Expense(id: "later", amount: 12, desc: "Later", date: date))
            try context.save()
            try BackupService.replaceAllExpenses(in: context, with: BackupService.parseBackup(data: backup))
            let liveRows = try context.fetch(FetchDescriptor<Expense>())
            XCTAssertEqual(liveRows.map(\.id), ["stable-id"])
            XCTAssertEqual(liveRows.first?.amount, 18.90)
        }
        let reopened = try container(at: url)
        let rows = try reopened.mainContext.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(rows.count, 1)
        let restored = try XCTUnwrap(rows.first)
        XCTAssertEqual(restored.id, "stable-id")
        XCTAssertEqual(restored.amount, 18.90)
        XCTAssertEqual(restored.desc, "Pharmacy")
        XCTAssertEqual(restored.splitMode, .fixed)
        XCTAssertEqual(restored.partnerShare, 10)
        XCTAssertEqual(restored.dateISO, "2026-09-14")
        XCTAssertEqual(restored.createdAt, date)
    }

    func testRejectedBackupLeavesExistingLedgerUntouched() throws {
        let store = try container()
        let context = store.mainContext
        context.insert(Expense(id: "keep", amount: 30, desc: "Keep", date: .now))
        try context.save()
        XCTAssertThrowsError(try BackupService.parseBackup(data: Data("{invalid".utf8)))
        let rows = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(rows.map(\.id), ["keep"])
        XCTAssertEqual(rows.first?.amount, 30)
    }

    func testEditingLargeAmountsRoundTripsInBothLanguages() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.shared.languagePreference = previous }
        for language in [AppLanguage.english, .german] {
            LanguageManager.shared.languagePreference = language
            let expense = Expense(amount: 1234.56, desc: "Rent", date: .now,
                                  splitMode: .fixed, splitValue: 500)
            let editor = ExpenseEditorViewModel()
            editor.prepareForEdit(expense)
            XCTAssertEqual(editor.parsedAmount, 1234.56, "Editing must preserve amounts above €1,000")
            XCTAssertEqual(editor.partnerShareAmount, 500)
            XCTAssertTrue(editor.canSave)
        }
    }

    func testTransferableExportsJSONThatCanBeRestored() async throws {
        let expense = Expense(id: "exported", amount: 12.50, desc: "Käse", date: .now,
                              splitMode: .percent, splitValue: 60)
        let data = try BackupService.exportBackup(expenses: [expense])
        let document = BackupDocument(data: data)
        let provider = NSItemProvider()
        provider.register(document)
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.json.identifier))
        let exported: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { bytes, error in
                if let error { continuation.resume(throwing: error) }
                else if let bytes { continuation.resume(returning: bytes) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
        XCTAssertEqual(exported, data)
        let store = try container()
        try BackupService.replaceAllExpenses(in: store.mainContext,
                                            with: BackupService.parseBackup(data: exported))
        let restored = try XCTUnwrap(store.mainContext.fetch(FetchDescriptor<Expense>()).first)
        XCTAssertEqual(restored.desc, "Käse")
        XCTAssertEqual(restored.partnerShare, 7.50)
    }

    /// Exercise the actual editor in a hosting view that changes size, as a
    /// resizable scene does. Attach renders for visual review, and check that
    /// the scrollable body retains a usable viewport at each size.
    /// Window-size coverage on the installed runtime, not a native Duo pose test.
    func testLedgerResizesWithoutLosingMonthOrEditorState() async throws {
        let store = try container()
        let list = ExpenseListViewModel()
        list.currentYear = 2026
        list.currentMonth = 9
        let editor = ExpenseEditorViewModel()
        editor.prepareForNew()
        editor.amountText = "84,30"
        editor.description = "Unfinished groceries"
        editor.setPartnerFraction(0.35)
        // Keep the draft in the owner without presenting a modal over layout checks.
        editor.isPresented = false
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let fixtures = [Expense(id: "resize-fixture", amount: 84.30, desc: "Weekly groceries", date: try XCTUnwrap(Expense.dateFromISO("2026-09-14")))]
        let host = UIHostingController(rootView: MainExpenseView(listVM: list, editorVM: editor,
            voiceVM: VoiceModeViewModel(), settingsVM: SettingsViewModel(), expenses: fixtures,
            onShowWelcomeGuide: {}, onCaptureModalDismissed: {})
            .modelContainer(store))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        for size in [CGSize(width: 320, height: 568), CGSize(width: 466, height: 678),
                     CGSize(width: 890, height: 626), CGSize(width: 626, height: 890),
                     CGSize(width: 320, height: 400)] {
            window.frame = CGRect(origin: .zero, size: size)
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let scroll = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? UIScrollView }.first)
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
            XCTAssertEqual(list.currentMonth, 9)
            XCTAssertEqual(list.currentYear, 2026)
            XCTAssertEqual(editor.amountText, "84,30")
            XCTAssertEqual(editor.description, "Unfinished groceries")
            XCTAssertEqual(editor.partnerPercent, 35)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "window-layout-\(Int(size.width))x\(Int(size.height))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testEditorResizingKeepsScrollableContentReachable() async throws {
        let store = try container()
        let editor = ExpenseEditorViewModel()
        editor.prepareForEdit(Expense(amount: 84.30, desc: "Weekly groceries", date: .now))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ExpenseEditorSheet(viewModel: editor)
            .environment(\.locale, Locale(identifier: "en"))
            .modelContainer(store))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        for size in [CGSize(width: 320, height: 400), CGSize(width: 700, height: 400),
                     CGSize(width: 393, height: 852), CGSize(width: 320, height: 400)] {
            window.frame = CGRect(origin: .zero, size: size)
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutIfNeeded()
            let scrolls = descendants(of: host.view).compactMap { $0 as? UIScrollView }
            let scroll = try XCTUnwrap(scrolls.first(where: { $0.bounds.height > 30 }))
            XCTAssertGreaterThan(scroll.bounds.width, 200)
            if size.height <= 400 {
                XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height,
                                     "The keypad must remain scrollable in a short window")
            }
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "editor-\(Int(size.width))x\(Int(size.height))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testWelcomeRemainsScrollableAfterResizing() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let previousLanguage = LanguageManager.shared.languagePreference
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
            LanguageManager.shared.languagePreference = previousLanguage
        }
        for language in [AppLanguage.english, .german] {
            LanguageManager.shared.languagePreference = language
            let host = UIHostingController(rootView: OnboardingView(isPresented: .constant(true), onDismiss: { _ in }))
            window.rootViewController = host
            window.makeKeyAndVisible()
            for size in [CGSize(width: 320, height: 400), CGSize(width: 700, height: 400),
                         CGSize(width: 393, height: 852), CGSize(width: 320, height: 400)] {
                window.frame = CGRect(origin: .zero, size: size)
                host.view.frame = window.bounds
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(700))
                host.view.layoutIfNeeded()
                let scroll = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? UIScrollView }.first)
                XCTAssertGreaterThan(scroll.bounds.height, 100)
                XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1,
                                         "Welcome must not require horizontal scrolling")
                if size.height <= 400 {
                    XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height,
                                         "The welcome actions must be reachable by scrolling in short windows")
                }
                let bottom = max(-scroll.adjustedContentInset.top,
                                 scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                host.view.layoutIfNeeded()
                XCTAssertEqual(scroll.contentOffset.y, bottom, accuracy: 1)
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "welcome-\(language.rawValue)-\(Int(size.width))x\(Int(size.height))-bottom"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testSupportingScreensKeepScrollableViewportsAcrossWindowSizes() async throws {
        let store = try container()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let sizes = [CGSize(width: 320, height: 400), CGSize(width: 390, height: 844),
                     CGSize(width: 900, height: 640), CGSize(width: 640, height: 900)]
        for largeText in [false, true] {
            for name in ["welcome", "settings", "mode-choice", "voice"] {
                let settings = SettingsViewModel()
                let voice = VoiceModeViewModel()
                #if targetEnvironment(simulator)
                voice.openScreenshotPreview()
                #endif
                let content: AnyView
                switch name {
                case "welcome": content = AnyView(OnboardingView(isPresented: .constant(true), onDismiss: { _ in }))
                case "settings": content = AnyView(SettingsSheet(viewModel: settings, expenses: [], onShowWelcomeGuide: {}))
                case "mode-choice": content = AnyView(VoiceModeSelectionView(viewModel: settings, onSelect: { _ in }, onCancel: {}))
                default: content = AnyView(VoiceSheet(viewModel: voice))
                }
                let host = UIHostingController(rootView: content
                    .environment(\.dynamicTypeSize, largeText ? .accessibility5 : .large)
                    .transaction { $0.disablesAnimations = true }
                    .modelContainer(store))
                let window = UIWindow(windowScene: scene)
                window.rootViewController = host
                window.makeKeyAndVisible()
                for size in sizes {
                    window.frame = CGRect(origin: .zero, size: size)
                    host.view.frame = window.bounds
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(180))
                    host.view.layoutIfNeeded()
                    let scrolls = descendants(of: host.view).compactMap { $0 as? UIScrollView }
                    XCTAssertFalse(scrolls.isEmpty, "\(name) must retain a scrollable content area")
                    for scroll in scrolls where !scroll.isHidden && scroll.bounds.width > 100 {
                        XCTAssertGreaterThan(scroll.bounds.height, 70, "\(name) must leave room for its content")
                        XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1,
                                                 "\(name) must not require horizontal scrolling")
                    }
                }
                window.isHidden = true
                previous?.makeKeyAndVisible()
                voice.cancelSession()
            }
        }
    }

    func testSuccessfulRestoreRefreshesMountedSwiftDataQuery() async throws {
        let store = try container()
        store.mainContext.insert(Expense(id: "keep", amount: 30, desc: "Before", date: .now))
        try store.mainContext.save()
        var displayed: [String] = []
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: RestoreQueryProbe { displayed = $0 }.modelContainer(store))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(displayed, ["keep:30.0:Before"])
        let updated = Expense(id: "keep", amount: 20, desc: "After", date: .now)
        try BackupService.replaceAllExpenses(in: store.mainContext, with: [ExpenseBackup(from: updated)])
        for _ in 0..<20 {
            if displayed == ["keep:20.0:After"] { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(displayed, ["keep:20.0:After"], "An already-mounted ledger must update after a successful isolated restore")
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

@MainActor
final class BackupFailureRegressionTests: XCTestCase {
    func testRestoreSaveFailurePreservesOriginalLedger() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("readonly.store")
        let schema = Schema([Expense.self])
        do {
            let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            store.mainContext.insert(Expense(id: "keep", amount: 24, desc: "Original", date: .now))
            try store.mainContext.save()
        }
        let readonly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: false)])
        let data = Data(#"[{"id":"replace","amount":8,"description":"New","date":"2026-09-21","splitMode":"percent","splitValue":50}]"#.utf8)
        XCTAssertThrowsError(try BackupService.replaceAllExpenses(in: readonly.mainContext,
            with: BackupService.parseBackup(data: data)))
        let rows = try readonly.mainContext.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(rows.map(\.id), ["keep"])
        XCTAssertEqual(rows.first?.amount, 24)
        let fresh = try ModelContext(readonly).fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(fresh.map(\.id), ["keep"])
        XCTAssertEqual(fresh.first?.amount, 24)
    }
}

@MainActor
final class VoiceInsertRegressionTests: XCTestCase {
    func testFailedVoiceInsertDoesNotRegisterOrDuplicateOnRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("readonly-voice.store")
        let schema = Schema([Expense.self])
        let date = try XCTUnwrap(Expense.dateFromISO("2026-10-23"))
        do {
            let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            store.mainContext.insert(Expense(id: "keep", amount: 24, desc: "Original", date: date))
            try store.mainContext.save()
        }
        let readonly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: false)])
        // Voice Save mints a new Expense identity on every tap.
        XCTAssertThrowsError(try Expense.insertCommitted(
            [Expense(id: "voice-1", amount: 4.5, desc: "Coffee", date: date)],
            into: readonly.mainContext))
        XCTAssertThrowsError(try Expense.insertCommitted(
            [Expense(id: "voice-2", amount: 4.5, desc: "Coffee", date: date)],
            into: readonly.mainContext),
            "A second Save after failure must not insert a different ID")
        let live = try readonly.mainContext.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(live.map(\.id), ["keep"])
        XCTAssertEqual(live.first?.amount, 24)
        let fresh = try ModelContext(readonly).fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(fresh.map(\.id), ["keep"])
        XCTAssertEqual(fresh.first?.amount, 24)
    }

    func testSuccessfulVoiceInsertAppearsInLiveAndFreshContext() throws {
        let store = try ModelContainer(for: Schema([Expense.self]),
            configurations: [ModelConfiguration(schema: Schema([Expense.self]), isStoredInMemoryOnly: true)])
        let date = try XCTUnwrap(Expense.dateFromISO("2026-10-23"))
        store.mainContext.insert(Expense(id: "keep", amount: 24, desc: "Original", date: date))
        try store.mainContext.save()
        try Expense.insertCommitted(
            [Expense(id: "coffee", amount: 4.5, desc: "Coffee", date: date, splitMode: .percent, splitValue: 50)],
            into: store.mainContext)
        let live = try store.mainContext.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(Set(live.map(\.id)), ["keep", "coffee"])
        XCTAssertEqual(live.first { $0.id == "coffee" }?.amount, 4.5)
        let fresh = try ModelContext(store).fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(Set(fresh.map(\.id)), ["keep", "coffee"])
    }
}

@MainActor
final class ExpenseValidationRegressionTests: XCTestCase {
    func testUnsafeBackupNumbersAndDatesAreRejectedBeforeReplacement() throws {
        let schema = Schema([Expense.self])
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        store.mainContext.insert(Expense(id: "keep", amount: 24, desc: "Original", date: .now))
        try store.mainContext.save()
        let base: [String: Any] = ["id": "new", "amount": 20, "description": "Coffee", "date": "2026-09-21", "splitMode": "percent", "splitValue": 50]
        let invalid: [(String, Any)] = [("splitValue", 1e30), ("splitValue", -1), ("splitValue", 101),
            ("amount", 1e300), ("amount", -5), ("amount", 0), ("amount", 0.001), ("id", " "),
            ("date", "2026-02-30"), ("date", "2026-9-01")]
        for (key, value) in invalid {
            var row = base
            row[key] = value
            let data = try JSONSerialization.data(withJSONObject: [row])
            XCTAssertThrowsError(try BackupService.parseBackup(data: data), "\(key): \(value)")
            let decoded = try JSONDecoder().decode([ExpenseBackup].self, from: data)
            XCTAssertThrowsError(try BackupService.replaceAllExpenses(in: store.mainContext, with: decoded))
            XCTAssertEqual(try store.mainContext.fetch(FetchDescriptor<Expense>()).map(\.id), ["keep"])
        }
        let duplicates = try JSONDecoder().decode([ExpenseBackup].self,
            from: JSONSerialization.data(withJSONObject: [base, base]))
        XCTAssertThrowsError(try BackupService.replaceAllExpenses(in: store.mainContext, with: duplicates))
    }

    func testInvalidAlreadyStoredSplitCanBeRenderedAndEditedWithoutTrapping() {
        for split in [1e30, Double.infinity, Double.nan, -1, 101] {
            let row = Expense(amount: 10, desc: "Invalid old row", date: .now, splitValue: split)
            XCTAssertEqual(ExpenseListViewModel().formatSplit(row), loc("InvalidSplit"))
            let editor = ExpenseEditorViewModel()
            editor.prepareForEdit(row)
            XCTAssertFalse(editor.canSave)
            XCTAssertTrue(editor.partnerFraction.isFinite)
        }
    }

    func testValidationAcceptsLimitsAndRejectsNonfiniteMoney() {
        XCTAssertTrue(ExpenseValidation.isValid(amount: 0.01, splitMode: .percent, splitValue: 0))
        XCTAssertTrue(ExpenseValidation.isValid(amount: ExpenseValidation.maximumAmount, splitMode: .percent, splitValue: 100))
        XCTAssertTrue(ExpenseValidation.isValid(amount: 10, splitMode: .fixed, splitValue: 20))
        for number in [Double.infinity, -Double.infinity, Double.nan] {
            XCTAssertFalse(ExpenseValidation.isValid(amount: number, splitMode: .percent, splitValue: 50))
            XCTAssertFalse(ExpenseValidation.isValid(amount: 10, splitMode: .fixed, splitValue: number))
        }
    }
}

final class PrivacyManifestRegressionTests: XCTestCase {
    func testAppPrivacyManifestDeclaresSystemBootTimeForElapsedCaptureTimers() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Maeuse/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let boot = types.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategorySystemBootTime" }
        XCTAssertEqual(boot?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["35F9.1"],
            "Apple capture uses ProcessInfo.systemUptime for endpoint timing; ITMS-91053 rejects a missing reason")
        let defaults = types.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" }
        XCTAssertEqual(defaults?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }
}

private struct RestoreQueryProbe: View {
    @Query private var expenses: [Expense]
    let changed: ([String]) -> Void
    var body: some View {
        let rows = expenses.map { "\($0.id):\($0.amount):\($0.desc)" }.sorted()
        Text(rows.joined(separator: ","))
            .onChange(of: rows, initial: true) { _, values in changed(values) }
    }
}
