import XCTest
@testable import BogiApp

final class AccountGateTests: XCTestCase {
    private func gate(token: String?, respond: @escaping (URLRequest) async throws -> (Data, URLResponse)) -> AccountGate {
        AccountGate(baseURL: URL(string: "https://example.com")!,
                    tokenProvider: { token },
                    transport: respond)
    }

    private func http(_ code: Int, _ json: String) -> (Data, URLResponse) {
        let resp = HTTPURLResponse(url: URL(string: "https://example.com/v1/account/status")!,
                                   statusCode: code, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), resp)
    }

    func testSignedOutWhenNoToken() async {
        let g = gate(token: nil) { _ in (Data(), URLResponse()) }
        let out = await g.check()
        XCTAssertEqual(out, .signedOut)
    }

    func testSignedInOn200() async {
        let g = gate(token: "t") { [self] _ in http(200, #"{"paid":false,"plan":null}"#) }
        let out = await g.check()
        XCTAssertEqual(out, .signedIn)
    }

    func testSignedOutOn401() async {
        let g = gate(token: "t") { [self] _ in http(401, #"{"error":"unauthorized"}"#) }
        let out = await g.check()
        XCTAssertEqual(out, .signedOut)
    }

    func testUnreachableOnThrow() async {
        struct Boom: Error {}
        let g = gate(token: "t") { _ in throw Boom() }
        let out = await g.check()
        XCTAssertEqual(out, .unreachable)
    }

    func testUnreachableOnNonHTTPResponse() async {
        let g = gate(token: "t") { _ in (Data(), URLResponse()) }
        let out = await g.check()
        XCTAssertEqual(out, .unreachable)
    }
}
