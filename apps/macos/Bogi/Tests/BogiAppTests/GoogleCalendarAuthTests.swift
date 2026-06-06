import XCTest
@testable import BogiApp

final class GoogleCalendarAuthTests: XCTestCase {

    // MARK: - Loopback HTTP request-target parsing

    func testRequestTargetExtractsPathAndQueryFromGetLine() {
        let raw = "GET /oauth2redirect?code=abc123&scope=calendar HTTP/1.1\r\nHost: 127.0.0.1:51234\r\n\r\n"
        XCTAssertEqual(
            LoopbackOAuthListener.requestTarget(fromHTTPRequest: raw),
            "/oauth2redirect?code=abc123&scope=calendar"
        )
    }

    func testRequestTargetHandlesRootPathWithoutQuery() {
        let raw = "GET / HTTP/1.1\r\n\r\n"
        XCTAssertEqual(LoopbackOAuthListener.requestTarget(fromHTTPRequest: raw), "/")
    }

    func testRequestTargetReturnsNilForMalformedRequest() {
        XCTAssertNil(LoopbackOAuthListener.requestTarget(fromHTTPRequest: ""))
        XCTAssertNil(LoopbackOAuthListener.requestTarget(fromHTTPRequest: "garbage without a method"))
        XCTAssertNil(LoopbackOAuthListener.requestTarget(fromHTTPRequest: "POST /oauth2redirect HTTP/1.1"))
    }

    // MARK: - PKCE

    func testPKCEChallengeIsBase64URLWithoutPaddingOrReservedChars() {
        let pkce = GoogleCalendarService.makePKCE()
        XCTAssertFalse(pkce.challenge.isEmpty)
        XCTAssertFalse(pkce.challenge.contains("="))
        XCTAssertFalse(pkce.challenge.contains("+"))
        XCTAssertFalse(pkce.challenge.contains("/"))
        XCTAssertEqual(pkce.verifier.count, 64)
    }
}
