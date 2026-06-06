import XCTest
@testable import BogiApp

/// Manual, opt-in LIVE integration test for the real Google Calendar flow. It opens your default
/// browser for consent, so it only runs when `BOGI_LIVE_GOOGLE=1` is set:
///
///     BOGI_LIVE_GOOGLE=1 swift test --filter GoogleCalendarLiveTests
///
/// It exercises the actual `GoogleCalendarService` end-to-end:
///   1. OAuth (loopback + PKCE) — complete consent in the browser that opens.
///   2. Read events from ALL of your calendars for the next 7 days (paginated).
///   3. Create a "Togi live test" event on your primary calendar (write-back).
///   4. Re-read and confirm the created event comes back from Google.
///
/// Side effects: leaves a "Togi live test" event on your primary calendar and stores tokens in your
/// login Keychain. Set `BOGI_LIVE_SIGNOUT=1` to remove the tokens again at the end. Requires that
/// your Google account is a Test user on the OAuth client (or that the app is published).
final class GoogleCalendarLiveTests: XCTestCase {

    @MainActor
    func testLiveConnectReadWrite() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BOGI_LIVE_GOOGLE"] == "1",
            "Set BOGI_LIVE_GOOGLE=1 to run the live Google Calendar test (it opens a browser)."
        )

        let service = GoogleCalendarService()
        let clientId = GoogleConfig.clientID
        let clientSecret = GoogleConfig.clientSecret

        // 1) OAuth — opens the browser; complete consent there (you have ~5 min).
        print("\n[live] Opening browser for Google consent…")
        try await service.authorize(clientId: clientId, clientSecret: clientSecret)
        print("[live] ✅ Authorized; tokens stored in Keychain.")

        // 2) Read events from all calendars for the next 7 days.
        let now = Date()
        let weekAhead = now.addingTimeInterval(7 * 86_400)
        let before = try await service.fetchEvents(
            start: now, end: weekAhead, clientId: clientId, clientSecret: clientSecret)
        print("[live] 📅 Read \(before.count) event(s) across all calendars:")
        for event in before.prefix(8) {
            print("       • \(event.title)  [\(event.calendarId ?? "?")]  \(event.start)")
        }

        // 3) Write-back: create a test event on the primary calendar.
        let start = now.addingTimeInterval(3600)
        let end = start.addingTimeInterval(1800)
        let eventId = try await service.createEvent(
            title: "Togi live test", start: start, end: end,
            clientId: clientId, clientSecret: clientSecret)
        print("[live] ✍️  Created event id=\(eventId) on primary calendar.")
        XCTAssertFalse(eventId.isEmpty, "Google should return an event id")

        // 4) Read back and confirm the created event is returned.
        let after = try await service.fetchEvents(
            start: now, end: weekAhead, clientId: clientId, clientSecret: clientSecret)
        let found = after.contains { $0.externalId == eventId }
        print("[live] 🔁 Created event present on re-read: \(found) (total now \(after.count)).")
        XCTAssertTrue(found, "the event Bogi created should come back from Google")

        if ProcessInfo.processInfo.environment["BOGI_LIVE_SIGNOUT"] == "1" {
            service.signOut()
            print("[live] 🔓 Signed out (tokens removed from Keychain).")
        }
        print("[live] Done — check your Google Calendar for the 'Togi live test' event.\n")
    }
}
