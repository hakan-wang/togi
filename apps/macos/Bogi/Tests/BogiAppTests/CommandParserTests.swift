import XCTest
@testable import BogiApp

final class CommandParserTests: XCTestCase {
    func testParsesRealityLogCommand() {
        let parser = CommandParser()
        XCTAssertEqual(
            parser.parse("Reality log: I edited for 45 minutes"),
            .saveRealityLog(text: "I edited for 45 minutes")
        )
    }

    func testParsesStartLockInCommand() {
        let parser = CommandParser()
        XCTAssertEqual(parser.parse("start lock in"), .startLockIn)
    }
}
