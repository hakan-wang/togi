import XCTest
@testable import BogiApp

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Test doubles

/// Captures the outgoing request and returns a canned response so we can assert
/// request building and status-code → error mapping without a network.
private final class StubTransport: HTTPTransport, @unchecked Sendable {
    var lastRequest: URLRequest?
    var responseData: Data
    var statusCode: Int
    var headerFields: [String: String]
    /// When set, `send` throws this instead of returning, simulating offline.
    var errorToThrow: Error?

    init(responseData: Data = Data(), statusCode: Int = 200, headerFields: [String: String] = [:]) {
        self.responseData = responseData
        self.statusCode = statusCode
        self.headerFields = headerFields
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let errorToThrow { throw errorToThrow }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
        return (responseData, response)
    }
}

private struct StubTokenProvider: AccessTokenProviding {
    var token: String?
    func accessToken() async -> String? { token }
}

// MARK: - Tests

final class AuthTests: XCTestCase {
    private let config = BackendConfig(baseURL: URL(string: "https://test.local")!)

    // MARK: InferenceClientLive — request building

    func testInferRequestBuilding() async throws {
        let transport = StubTransport(
            responseData: Data(#"{"text":"hi there"}"#.utf8),
            statusCode: 200
        )
        let client = InferenceClientLive(
            config: config,
            tokenProvider: StubTokenProvider(token: "test-jwt"),
            transport: transport
        )

        let request = InferenceRequest(
            messages: [InferenceMessage(role: .user, content: "hello")],
            maxTokens: 256
        )
        _ = try await client.infer(request)

        let sent = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(sent.url, URL(string: "https://test.local/v1/infer"))
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer test-jwt")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(sent.httpBody)
        let json = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(json.contains("\"max_tokens\":256"), "body must use snake_case: \(json)")

        let decoded = try JSONDecoder().decode(InferenceRequest.self, from: body)
        XCTAssertEqual(decoded.maxTokens, 256)
        XCTAssertEqual(decoded.messages, [InferenceMessage(role: .user, content: "hello")])
    }

    // MARK: InferenceClientLive — status-code → error mapping

    func testInferDecodesSuccess() async throws {
        let transport = StubTransport(
            responseData: Data(#"{"text":"the answer"}"#.utf8),
            statusCode: 200
        )
        let client = makeClient(transport: transport, token: "jwt")
        let response = try await client.infer(sampleRequest())
        XCTAssertEqual(response.text, "the answer")
    }

    func testInferMapsUnauthorized() async {
        let client = makeClient(transport: StubTransport(statusCode: 401), token: "jwt")
        await assertInferError(client, expected: .notAuthenticated)
    }

    func testInferMapsPaymentRequired() async {
        let client = makeClient(transport: StubTransport(statusCode: 402), token: "jwt")
        await assertInferError(client, expected: .notPaid)
    }

    func testInferMapsForbiddenToNotPaid() async {
        let client = makeClient(transport: StubTransport(statusCode: 403), token: "jwt")
        await assertInferError(client, expected: .notPaid)
    }

    func testInferMapsOtherStatus() async {
        let client = makeClient(transport: StubTransport(statusCode: 500), token: "jwt")
        await assertInferError(client, expected: .http(status: 500))
    }

    func testInferMapsDecodeFailure() async {
        let transport = StubTransport(responseData: Data("not json".utf8), statusCode: 200)
        let client = makeClient(transport: transport, token: "jwt")
        await assertInferError(client, expected: .decoding)
    }

    func testInferRequiresToken() async {
        // No token → fail fast before any network call.
        let transport = StubTransport(statusCode: 200)
        let client = makeClient(transport: transport, token: nil)
        await assertInferError(client, expected: .notAuthenticated)
        XCTAssertNil(transport.lastRequest, "should not hit the network without a token")
    }

    // MARK: AccountStatusClient

    func testAccountStatusDecodesAndBuildsRequest() async throws {
        let transport = StubTransport(
            responseData: Data(#"{"paid":true,"plan":"pro"}"#.utf8),
            statusCode: 200
        )
        let checker = AccountStatusClient(config: config, transport: transport)
        let status = try await checker.fetchStatus(accessToken: "jwt")

        XCTAssertEqual(status, AccountStatus(paid: true, plan: "pro"))
        let sent = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(sent.url, URL(string: "https://test.local/v1/account/status"))
        XCTAssertEqual(sent.httpMethod, "GET")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
    }

    func testAccountStatusMapsUnauthorized() async {
        let checker = AccountStatusClient(config: config, transport: StubTransport(statusCode: 401))
        await XCTAssertThrowsErrorAsync(try await checker.fetchStatus(accessToken: "jwt")) { error in
            XCTAssertEqual(error as? AccountStatusError, .notAuthenticated)
        }
    }

    func testAccountStatusMapsOtherStatus() async {
        let checker = AccountStatusClient(config: config, transport: StubTransport(statusCode: 503))
        await XCTAssertThrowsErrorAsync(try await checker.fetchStatus(accessToken: "jwt")) { error in
            XCTAssertEqual(error as? AccountStatusError, .http(status: 503))
        }
    }

    // MARK: AccountGate.shouldBlock — pure decision logic

    func testShouldBlockWhenNoSession() {
        XCTAssertTrue(AccountGate.shouldBlock(session: nil, paid: true))
        XCTAssertTrue(AccountGate.shouldBlock(session: nil, paid: false))
    }

    func testShouldBlockWhenUnpaid() {
        XCTAssertTrue(AccountGate.shouldBlock(session: sampleSession(), paid: false))
    }

    func testShouldNotBlockWhenSignedInAndPaid() {
        XCTAssertFalse(AccountGate.shouldBlock(session: sampleSession(), paid: true))
    }

    func testGateStateMapping() {
        XCTAssertEqual(AccountGate.gateState(session: nil, paid: true), .needsLogin)
        XCTAssertEqual(AccountGate.gateState(session: sampleSession(), paid: false), .needsPayment)
        XCTAssertEqual(AccountGate.gateState(session: sampleSession(), paid: true), .allowed)
    }

    // MARK: BackendConfig resolution

    func testBackendConfigResolvesFromEnvironment() {
        let resolved = BackendConfig.resolved(
            environment: ["BOGI_BACKEND_BASE_URL": "https://env.example.com"],
            bundle: .main
        )
        XCTAssertEqual(resolved.baseURL, URL(string: "https://env.example.com"))
        XCTAssertEqual(resolved.inferURL, URL(string: "https://env.example.com/v1/infer"))
        XCTAssertEqual(resolved.accountStatusURL, URL(string: "https://env.example.com/v1/account/status"))
    }

    func testBackendConfigFallsBackToProduction() {
        let resolved = BackendConfig.resolved(environment: [:], bundle: .main)
        XCTAssertEqual(resolved.baseURL, BackendConfig.production.baseURL)
    }

    // MARK: Helpers

    private func makeClient(transport: HTTPTransport, token: String?) -> InferenceClientLive {
        InferenceClientLive(
            config: config,
            tokenProvider: StubTokenProvider(token: token),
            transport: transport
        )
    }

    private func sampleRequest() -> InferenceRequest {
        InferenceRequest(messages: [InferenceMessage(role: .user, content: "hi")], maxTokens: 64)
    }

    private func sampleSession() -> AuthSession {
        AuthSession(userId: "user-1", accessToken: "jwt", email: "a@b.com")
    }

    private func assertInferError(
        _ client: InferenceClientLive,
        expected: InferenceError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await client.infer(sampleRequest())
            XCTFail("expected \(expected) but call succeeded", file: file, line: line)
        } catch let error as InferenceError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected InferenceError.\(expected) but got \(error)", file: file, line: line)
        }
    }
}

// MARK: - Async throwing assertion helper

extension XCTestCase {
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message.isEmpty ? "expected an error to be thrown" : message, file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
