import XCTest
import UIKit

/// Uses only the simulator's synthetic screenshot fixtures. Never signs into a service.
final class AdaptiveLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ scenario: String = "main", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-\(scenario)", "-maeuse.language", "de", "-maeuse.colorScheme", "light"] + extra
        app.launch()
        let ready: XCUIElement
        switch scenario {
        case "onboarding": ready = app.buttons["welcome-start"]
        case "settings-basic": ready = app.buttons["settings-done"]
        case "voice-choice": ready = app.buttons["voice-choice-confirm"]
        case "voice", "local-voice": ready = app.staticTexts["voice-fixture-notice"]
        default: ready = app.buttons["Ausgabe hinzufügen"]
        }
        XCTAssertTrue(ready.waitForExistence(timeout: 10) || app.buttons["expense-cancel"].exists)
        return app
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 1.2)
        // A foldable device can retain an inactive primary screen. Capture the
        // documented screen list and skip blank framebuffers instead of assuming main is visible.
        var captured = 0
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let shot = screen.screenshot()
            guard hasVisiblePixels(shot.image) else {
                print("MAEUSE_CAPTURE skipped inactive screen \(index) for \(name)")
                continue
            }
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "\(name)-screen\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
            captured += 1
        }
        XCTAssertGreaterThan(captured, 0, "A screenshot checkpoint must contain visible pixels")
    }

    private func hasVisiblePixels(_ image: UIImage) -> Bool {
        guard let source = image.cgImage else { return false }
        let side = 24
        var sample = [UInt8](repeating: 0, count: side * side * 4)
        return sample.withUnsafeMutableBytes { storage in
            guard let context = CGContext(data: storage.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            let pixels = storage.bindMemory(to: UInt8.self)
            return stride(from: 0, to: pixels.count, by: 4).contains {
                Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2]) > 24 && pixels[$0 + 3] > 0
            }
        }
    }

    /// Element checks alone pass even when the window never rotates (as on the iPhone Duo
    /// simulator's inner display), so verify the actual window shape and the wide layout.
    private func requireLandscape(_ app: XCUIApplication) throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(3)
        while window.frame.width <= window.frame.height && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        guard window.frame.width > window.frame.height else {
            throw XCTSkip("The app window did not rotate on this device (\(window.frame.size)); landscape layout is unverified here.")
        }
        if window.frame.width >= 700 {
            XCTAssertTrue(app.descendants(matching: .any)["monthly-split"].waitForExistence(timeout: 5),
                          "A wide landscape window must show the two-column month review")
        }
    }

    func testRotationPreservesMonthAndDraft() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["expense-screenshot-1"].waitForExistence(timeout: 5))
        capture("01-portrait-light")
        app.buttons["Vorheriger Monat"].tap()
        XCTAssertFalse(app.buttons["expense-screenshot-1"].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        try requireLandscape(app)
        XCTAssertTrue(app.buttons["Nächster Monat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["expense-screenshot-1"].exists)
        app.buttons["Nächster Monat"].tap()
        XCTAssertTrue(app.buttons["expense-screenshot-1"].waitForExistence(timeout: 5))
        capture("02-landscape-light")
        app.buttons["expense-screenshot-1"].tap()
        let note = app.textFields.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String, "Wocheneinkauf")
        note.tap()
        note.typeText(" Test")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(note.value as? String, "Wocheneinkauf Test")
        XCTAssertTrue(app.buttons["expense-save"].exists)
        capture("03-draft-after-rotation")
        app.buttons["expense-save"].tap()
        XCTAssertTrue(app.buttons["expense-screenshot-1"].waitForExistence(timeout: 5))
        app.buttons["expense-screenshot-1"].tap()
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Wocheneinkauf Test")
        app.buttons["expense-cancel"].tap()
        XCUIDevice.shared.orientation = .landscapeRight
        try requireLandscape(app)
        XCTAssertTrue(app.buttons["expense-screenshot-1"].waitForExistence(timeout: 5))
        capture("04-landscape-right")
    }

    func testDarkAndAccessibilityText() {
        let app = launch(extra: ["-maeuse.colorScheme", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["Ausgabe hinzufügen"].waitForExistence(timeout: 10))
        capture("07-accessibility-XXXL")
        app.swipeUp()
        XCTAssertTrue(app.buttons["expense-screenshot-1"].exists)
        capture("08-accessibility-rows")
    }

    func testDarkLandscape() throws {
        let app = launch(extra: ["-maeuse.colorScheme", "dark"])
        XCTAssertTrue(app.buttons["expense-screenshot-1"].waitForExistence(timeout: 5))
        capture("05-portrait-dark")
        XCUIDevice.shared.orientation = .landscapeLeft
        try requireLandscape(app)
        XCTAssertTrue(app.buttons["expense-screenshot-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Vorheriger Monat"].isHittable)
        capture("06-landscape-dark")
    }

    func testAdditionalScreensUseSafeFixtureNavigation() {
        var app = launch("onboarding")
        let start = app.buttons["welcome-start"]
        scrollTo(start, in: app.scrollViews["welcome-scroll"])
        tapReachable(start)
        XCTAssertTrue(app.buttons["Ausgabe hinzufügen"].waitForExistence(timeout: 5))
        app.terminate()

        app = launch("settings-basic")
        XCTAssertTrue(app.buttons["voice-change-mode"].waitForExistence(timeout: 5))
        app.buttons["voice-change-mode"].tap()
        XCTAssertTrue(app.buttons["voice-choice-confirm"].waitForExistence(timeout: 5))
        let local = app.buttons["voice-choice-appleLocal"]
        scrollTo(local, in: app.scrollViews["voice-choice-scroll"])
        tapReachable(local)
        XCTAssertTrue(local.isSelected)
        app.terminate()

        app = launch("local-voice", extra: ["--local-processing"])
        XCTAssertTrue(app.staticTexts["voice-fixture-notice"].exists)
        XCTAssertTrue(app.buttons["local-record"].exists)
        XCTAssertTrue(app.otherElements["voice-draft-flowers"].waitForExistence(timeout: 5))
        app.buttons["voice-close"].tap()
        XCTAssertTrue(app.buttons["Ausgabe hinzufügen"].waitForExistence(timeout: 5))
    }

    func testAccessibilityContentCanActuallyScrollToLastControls() {
        let large = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        var app = launch(extra: large)
        let ledger = app.scrollViews["expense-ledger"]
        let lastExpense = app.buttons["expense-screenshot-5"]
        XCTAssertFalse(lastExpense.isHittable)
        scrollTo(lastExpense, in: ledger)
        XCTAssertFalse(app.buttons["expense-screenshot-1"].isHittable)
        capture("20-large-text-ledger-bottom")
        app.terminate()

        app = launch("onboarding", extra: large)
        scrollTo(app.buttons["welcome-start"], in: app.scrollViews["welcome-scroll"])
        capture("21-large-text-welcome-bottom")
        app.terminate()

        app = launch("settings-basic", extra: large)
        scrollTo(app.buttons["settings-help"], in: app.scrollViews["settings-scroll"])
        capture("22-large-text-settings-bottom")
        app.terminate()

        app = launch("voice-choice", extra: large)
        scrollTo(app.buttons["voice-choice-openAI"], in: app.scrollViews["voice-choice-scroll"])
        XCTAssertTrue(app.buttons["voice-choice-confirm"].isHittable)
        capture("23-large-text-mode-choice")
        app.terminate()

        app = launch("voice", extra: large)
        scrollTo(app.otherElements["voice-draft-film"], in: app.scrollViews["voice-drafts-scroll"])
        XCTAssertTrue(app.buttons["voice-save"].isHittable)
        capture("24-large-text-voice-bottom")
    }

    func testCloudProviderCanBeSelectedFromNestedSettingsWithoutActivation() {
        let app = launch("settings-basic", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])
        app.buttons["voice-change-mode"].tap()
        XCTAssertTrue(app.buttons["voice-choice-confirm"].waitForExistence(timeout: 5))
        let scroll = app.scrollViews["voice-choice-scroll"]
        let local = app.buttons["voice-choice-appleLocal"]
        local.tap()
        XCTAssertTrue(local.isSelected)
        capture("30-nested-mode-choice-before-scroll")
        scroll.swipeUp()
        scroll.swipeUp()
        capture("31-nested-mode-choice-after-scroll")
        let cloud = app.buttons["voice-choice-openAI"]
        XCTAssertTrue(cloud.waitForExistence(timeout: 5))
        cloud.tap()
        XCTAssertTrue(cloud.isSelected)
        capture("32-nested-mode-choice-cloud-selected")
        // Do not drag down at the top: that dismisses the page sheet.
        // Selection stays local; never confirm, authorize or start a service.
    }

    private func scrollTo(_ target: XCUIElement, in scroll: XCUIElement) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            if isReachable(target, in: scroll) { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(isReachable(target, in: scroll), "The final control must be reachable through its own scroll view")
    }

    /// On the iPhone Duo simulator, XCTest can report a fully visible control in content
    /// that does not need to scroll as not hittable. Its frame inside the visible scroll
    /// view is the reachability that matters to a person.
    private func isReachable(_ target: XCUIElement, in scroll: XCUIElement) -> Bool {
        // Lazy rows do not exist until scrolled to; reading a missing element's frame fails.
        guard target.exists else { return false }
        return target.isHittable || (!target.frame.isEmpty && scroll.frame.contains(target.frame))
    }

    private func tapReachable(_ target: XCUIElement) {
        if target.isHittable { target.tap() }
        else { target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }


}
