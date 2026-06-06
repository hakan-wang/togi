import XCTest
@testable import BogiApp

final class GateStateTests: XCTestCase {
    func testMapping() {
        XCTAssertEqual(GateState(for: .subscribed), .unlocked)
        XCTAssertEqual(GateState(for: .notSubscribed), .needsSubscription)
        XCTAssertEqual(GateState(for: .signedOut), .needsLogin)
        XCTAssertEqual(GateState(for: .unreachable), .blocked)
    }
}
