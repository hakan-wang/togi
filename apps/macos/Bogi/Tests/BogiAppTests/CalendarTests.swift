import XCTest
@testable import BogiApp

final class CalendarTests: XCTestCase {
    // MARK: - PKCE (RFC 7636 test vector, Appendix B)

    func testPKCEChallengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertEqual(PKCE.challenge(for: verifier), expected)
    }

    func testPKCEBase64URLHasNoPaddingOrUnsafeChars() {
        // Bytes chosen so standard base64 would contain '+', '/' and '='.
        let data = Data([0xfb, 0xff, 0xbf, 0x00])
        let encoded = PKCE.base64URLEncode(data)
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
    }

    func testPKCEGenerateIsDeterministicForFixedBytes() {
        let bytes = Array(UInt8(0)..<UInt8(32))
        let pair = PKCE.generate(randomBytes: { bytes })
        XCTAssertEqual(pair.method, "S256")
        XCTAssertEqual(pair.verifier, PKCE.makeVerifier(from: bytes))
        XCTAssertEqual(pair.challenge, PKCE.challenge(for: pair.verifier))
    }

    // MARK: - Token refresh decision

    func testTokenDecisionUsableWhenFresh() {
        let token = OAuthToken(accessToken: "a", refreshToken: "r",
                               expiresAt: TestClock.reference.addingTimeInterval(3600))
        XCTAssertEqual(TokenLogic.decision(for: token, now: TestClock.reference), .usable)
    }

    func testTokenDecisionRefreshWhenExpiringWithRefreshToken() {
        let token = OAuthToken(accessToken: "a", refreshToken: "r",
                               expiresAt: TestClock.reference.addingTimeInterval(30))
        XCTAssertEqual(TokenLogic.decision(for: token, now: TestClock.reference, leeway: 60), .refresh)
    }

    func testTokenDecisionReauthWhenExpiredWithoutRefreshToken() {
        let token = OAuthToken(accessToken: "a", refreshToken: nil,
                               expiresAt: TestClock.reference.addingTimeInterval(-10))
        XCTAssertEqual(TokenLogic.decision(for: token, now: TestClock.reference), .reauthenticate)
    }

    func testTokenDecisionReauthWhenNil() {
        XCTAssertEqual(TokenLogic.decision(for: nil, now: TestClock.reference), .reauthenticate)
    }

    func testTokenDecisionFromHTTPStatus() {
        let withRefresh = OAuthToken(accessToken: "a", refreshToken: "r", expiresAt: TestClock.reference)
        let noRefresh = OAuthToken(accessToken: "a", refreshToken: nil, expiresAt: TestClock.reference)
        XCTAssertEqual(TokenLogic.decision(forStatus: 401, token: withRefresh), .refresh)
        XCTAssertEqual(TokenLogic.decision(forStatus: 401, token: noRefresh), .reauthenticate)
        XCTAssertEqual(TokenLogic.decision(forStatus: 200, token: withRefresh), .usable)
    }

    // MARK: - Ownership tagging

    func testEventTagRoundTrip() {
        let annotated = CalendarEventTag.annotate(notes: "Lunch with team", blockId: "abc-123")
        XCTAssertTrue(CalendarEventTag.isBogiCreated(notes: annotated))
        XCTAssertEqual(CalendarEventTag.blockId(fromNotes: annotated), "abc-123")
        XCTAssertEqual(CalendarEventTag.strip(notes: annotated), "Lunch with team")
    }

    func testEventTagAbsentForUserEvent() {
        XCTAssertFalse(CalendarEventTag.isBogiCreated(notes: "Just a normal event"))
        XCTAssertNil(CalendarEventTag.blockId(fromNotes: nil))
    }

    func testEventTagDoesNotDuplicate() {
        let once = CalendarEventTag.annotate(notes: nil, blockId: "x")
        let twice = CalendarEventTag.annotate(notes: once, blockId: "x")
        XCTAssertEqual(twice.components(separatedBy: CalendarEventTag.open).count - 1, 1)
    }

    // MARK: - OAuth URL building

    func testAuthorizationURLContainsPKCEAndState() throws {
        let config = GoogleOAuthConfig(clientId: "client.apps.googleusercontent.com",
                                       redirectURI: "com.bogi.app:/oauth")
        let pkce = PKCEPair(verifier: "v", challenge: "chal")
        let url = try XCTUnwrap(GoogleOAuthURLBuilder.authorizationURL(config: config, pkce: pkce, state: "xyz"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("code_challenge"), "chal")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("state"), "xyz")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("access_type"), "offline")
        XCTAssertNil(value("client_secret"))
    }

    func testAuthorizationCodeRejectsStateMismatch() {
        let good = URL(string: "com.bogi.app:/oauth?code=abc&state=expected")!
        let bad = URL(string: "com.bogi.app:/oauth?code=abc&state=attacker")!
        XCTAssertEqual(GoogleOAuthURLBuilder.authorizationCode(fromCallback: good, expectedState: "expected"), "abc")
        XCTAssertNil(GoogleOAuthURLBuilder.authorizationCode(fromCallback: bad, expectedState: "expected"))
    }

    func testTokenExchangeBodyHasVerifierAndNoSecret() throws {
        let config = GoogleOAuthConfig(clientId: "cid", redirectURI: "com.bogi.app:/oauth")
        let body = try XCTUnwrap(GoogleOAuthURLBuilder.tokenExchangeBody(config: config, code: "thecode", verifier: "theverifier"))
        let string = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(string.contains("code_verifier=theverifier"))
        XCTAssertTrue(string.contains("grant_type=authorization_code"))
        XCTAssertFalse(string.contains("client_secret"))
    }

    // MARK: - Token store + refresh (mocked, no Keychain/network)

    func testKeychainlessTokenStoreRoundTrips() throws {
        let store = InMemoryTokenStore()
        let token = OAuthToken(accessToken: "acc", refreshToken: "ref",
                               expiresAt: TestClock.reference, scope: "calendar")
        try store.save(token, account: "default")
        XCTAssertEqual(try store.load(account: "default"), token)
        try store.delete(account: "default")
        XCTAssertNil(try store.load(account: "default"))
    }

    func testGoogleTokenResponseMapsExpiresIn() {
        let response = GoogleTokenResponse(access_token: "acc", expires_in: 3600,
                                           refresh_token: nil, scope: "calendar")
        let token = response.token(now: TestClock.reference, fallbackRefreshToken: "kept-refresh")
        XCTAssertEqual(token.accessToken, "acc")
        // Google omits refresh_token on refresh; we keep the prior one.
        XCTAssertEqual(token.refreshToken, "kept-refresh")
        XCTAssertEqual(token.expiresAt, TestClock.reference.addingTimeInterval(3600))
    }

    // MARK: - Google event mapping

    func testGoogleEventMappingDetectsBogiOwnership() {
        let item = GoogleEventsResponse.Item(
            id: "evt-1", summary: "Edit videos",
            description: "Planned by Bogi\n\n\(CalendarEventTag.marker(for: "blk-9"))",
            start: .init(dateTime: "2026-06-06T09:00:00Z", date: nil),
            end: .init(dateTime: "2026-06-06T10:00:00Z", date: nil),
            updated: "2026-06-06T08:30:00Z"
        )
        let event = GoogleEventMapper.map(item, calendarId: "primary")
        XCTAssertEqual(event?.title, "Edit videos")
        XCTAssertEqual(event?.provider, .google)
        XCTAssertTrue(event?.isBogiCreated == true)
        XCTAssertEqual(event?.bogiBlockId, "blk-9")
    }

    func testGoogleEventMappingSkipsAllDayEvents() {
        let item = GoogleEventsResponse.Item(
            id: "evt-2", summary: "Holiday", description: nil,
            start: .init(dateTime: nil, date: "2026-06-06"),
            end: .init(dateTime: nil, date: "2026-06-07"),
            updated: nil
        )
        XCTAssertNil(GoogleEventMapper.map(item, calendarId: "primary"))
    }
}
