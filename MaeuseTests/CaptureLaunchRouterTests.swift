import Foundation
import XCTest
@testable import Maeuse

final class CaptureLaunchRouterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = CaptureLaunchRouter.consumePending()
    }

    override func tearDown() {
        _ = CaptureLaunchRouter.consumePending()
        super.tearDown()
    }

    func testSetAndConsumePendingAddExpense() {
        CaptureLaunchRouter.setPending(.addExpense)
        XCTAssertEqual(CaptureLaunchRouter.peekPending(), .addExpense)
        XCTAssertEqual(CaptureLaunchRouter.consumePending(), .addExpense)
        XCTAssertNil(CaptureLaunchRouter.consumePending())
    }

    func testSetAndConsumePendingDictateExpense() {
        CaptureLaunchRouter.setPending(.dictateExpense)
        XCTAssertEqual(CaptureLaunchRouter.consumePending(), .dictateExpense)
        XCTAssertNil(CaptureLaunchRouter.peekPending())
    }

    func testCaptureURLsRoundTripBothDestinations() {
        for destination in [CaptureLaunchDestination.addExpense, .dictateExpense] {
            let url = CaptureLaunchRouter.url(for: destination)
            XCTAssertEqual(url.scheme, "maeuse")
            XCTAssertEqual(CaptureLaunchRouter.destination(from: url), destination)
        }
    }

    func testUnrelatedURLIsIgnored() {
        XCTAssertNil(CaptureLaunchRouter.destination(from: URL(string: "https://example.com/capture/addExpense")!))
    }
}
