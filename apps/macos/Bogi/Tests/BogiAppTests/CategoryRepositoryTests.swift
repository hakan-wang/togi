import XCTest
@testable import BogiApp

final class CategoryRepositoryTests: XCTestCase {
    private func repo() throws -> CategoryRepository {
        CategoryRepository(database: try DatabaseService(inMemory: true))
    }

    func testAllReturnsSeededNine() throws {
        let all = try repo().all()
        XCTAssertEqual(all.count, 9)
        XCTAssertEqual(all.first?.id, "deepwork")           // sort_order 0
        XCTAssertEqual(all.first?.color, "#2E5BFF")
    }

    func testExistsAndColor() throws {
        let r = try repo()
        XCTAssertTrue(r.exists("scroll"))
        XCTAssertFalse(r.exists("nope"))
        XCTAssertEqual(r.color(for: "health"), "#22C55E")
        XCTAssertNil(r.color(for: "nope"))
    }
}
