import XCTest
@testable import BogiApp

final class CalendarAuthorizationStateTests: XCTestCase {
    func testDeniedStateRequiresUserAction() {
        XCTAssertTrue(CalendarAuthorizationState.denied.requiresUserAction)
        XCTAssertFalse(CalendarAuthorizationState.authorized.requiresUserAction)
    }
}
