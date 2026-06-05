import XCTest
@testable import BogiApp

final class PrivacyActionTests: XCTestCase {
    func testDeleteCloudDataRequiresConfirmation() {
        XCTAssertTrue(PrivacyAction.deleteCloudData.requiresConfirmation)
        XCTAssertFalse(PrivacyAction.exportData.requiresConfirmation)
    }
}
