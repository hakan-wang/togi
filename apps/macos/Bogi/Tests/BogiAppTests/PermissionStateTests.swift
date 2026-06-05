import XCTest
@testable import BogiApp

final class PermissionStateTests: XCTestCase {
    func testAccessibilityDeniedIsNotUsable() {
        XCTAssertFalse(PermissionState.denied.isUsable)
        XCTAssertTrue(PermissionState.granted.isUsable)
    }
}
