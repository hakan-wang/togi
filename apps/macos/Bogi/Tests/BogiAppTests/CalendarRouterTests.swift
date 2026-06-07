import XCTest
@testable import BogiApp

/// Routing-decision guards for CalendarRouter. These are pure (no network, no Keychain tokens),
/// so they pin the "when do we go to Google vs Apple" logic that the voice scheduler depends on.
final class CalendarRouterTests: XCTestCase {
    private func makeSettings() throws -> SettingsStore {
        SettingsStore(database: try DatabaseService(inMemory: true))
    }

    func testNoClientIdMeansGoogleNotConnected() throws {
        let settings = try makeSettings()
        let router = CalendarRouter(eventKit: EventKitService(), settings: settings)
        XCTAssertFalse(router.googleConnected)
        XCTAssertFalse(router.googleConfiguredButNotConnected)
    }

    func testClientIdWithoutTokenIsConfiguredButNotConnected() throws {
        let settings = try makeSettings()
        settings.set("google_client_id", "test-client-id.apps.googleusercontent.com")
        let router = CalendarRouter(eventKit: EventKitService(), settings: settings)
        router.disconnectGoogle()   // guarantee a clean slate (no leftover token on this machine)
        // No token in the Keychain for this account, so it's configured but not yet connected,
        // and booking must not claim Google is ready.
        XCTAssertFalse(router.googleConnected)
        XCTAssertTrue(router.googleConfiguredButNotConnected)
    }
}
