import XCTest
@testable import BogiApp

final class PlannedBlockRepositoryTests: XCTestCase {
    func testInsertAndFetchPlannedBlock() throws {
        let database = try DatabaseService(inMemory: true)
        let repository = PlannedBlockRepository(dbQueue: database.dbQueue)
        let block = PlannedBlock(
            id: "block_1",
            source: "local",
            externalEventID: nil,
            title: "Editing",
            startAt: Date(timeIntervalSince1970: 100),
            endAt: Date(timeIntervalSince1970: 200),
            category: "video_editing",
            goalID: nil,
            status: "planned",
            createdByBogi: true,
            updatedAt: Date(timeIntervalSince1970: 50)
        )

        try repository.save(block)
        XCTAssertEqual(try repository.fetch(id: "block_1"), block)
    }
}
