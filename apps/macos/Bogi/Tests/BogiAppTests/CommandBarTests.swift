import XCTest
@testable import BogiApp

final class CommandBarTests: XCTestCase {
    @MainActor
    func testCommandBarInitialStateIsHiddenAndEmpty() {
        let model = CommandBarModel()
        XCTAssertFalse(model.isPresented)
        XCTAssertEqual(model.query, "")
    }
}
