import XCTest
@testable import BogiApp

/// A bare `swift build`/test binary is NOT an `.app` bundle, so calling
/// `UNUserNotificationCenter.current()` throws an *uncatchable* `NSInternalInconsistencyException`
/// ("bundleProxyForCurrentProcess is nil") and hard-crashes the whole process. The authorizer must
/// detect the non-bundle context, skip the notification center entirely, and redirect the user to
/// System Settings — keeping the onboarding flow alive instead of taking the app down.
@MainActor
final class NotificationAuthorizerTests: XCTestCase {
    func testUnbundledContextRedirectsInsteadOfCrashing() async {
        var openedSettings = false
        let authorizer = NotificationAuthorizer(isBundledApp: { false },
                                                openSettings: { openedSettings = true })

        let granted = await authorizer.request()

        XCTAssertFalse(granted, "an unbundled process can never be granted notification permission")
        XCTAssertTrue(openedSettings, "it should redirect to System Settings rather than crash")
    }
}
