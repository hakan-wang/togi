import XCTest
@testable import BogiApp

final class ScreenContextPolicyTests: XCTestCase {
    func testOCRRequiresPermissionAndActiveMode() {
        let policy = ScreenContextPolicy(
            screenRecordingPermission: .granted,
            isLockInActive: true,
            isExplicitContextCommand: false
        )
        XCTAssertTrue(policy.canUseOCRFallback)
    }
}
