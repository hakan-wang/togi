import XCTest
@testable import BogiApp

final class LockInControllerTests: XCTestCase {
    @MainActor
    func testStartCreatesActiveSession() {
        let controller = LockInController()
        controller.start(blockID: "block_1")
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.currentSession?.blockID, "block_1")
    }
}
