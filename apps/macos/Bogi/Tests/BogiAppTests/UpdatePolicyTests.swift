import XCTest
@testable import BogiApp

final class UpdatePolicyTests: XCTestCase {
    func testBetaBuildCanCheckForUpdates() {
        XCTAssertTrue(UpdatePolicy(channel: .beta).canCheckForUpdates)
    }
}
