import XCTest
@testable import BogiApp

final class GateStateTests: XCTestCase {
    func testMapping() {
        XCTAssertEqual(GateState(for: .signedIn), .unlocked)
        XCTAssertEqual(GateState(for: .signedOut), .needsLogin)
        XCTAssertEqual(GateState(for: .unreachable), .blocked)
    }
}
