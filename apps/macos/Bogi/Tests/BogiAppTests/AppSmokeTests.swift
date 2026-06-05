import XCTest
@testable import BogiApp

final class AppSmokeTests: XCTestCase {
    func testAppMetadataIsStable() {
        XCTAssertEqual(AppMetadata.name, "Bogi")
        XCTAssertEqual(AppMetadata.minimumMacOSMajorVersion, 14)
    }
}
