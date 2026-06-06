import XCTest
@testable import BogiApp

final class FakeTransport: SidecarTransport {
    var onLine: ((String) -> Void)?
    var onTerminate: (() -> Void)?
    private(set) var sent: [String] = []
    private(set) var startCount = 0
    var autoReply: ((String) -> String?)?
    func start() throws { startCount += 1 }
    func stop() {}
    func send(_ line: String) {
        sent.append(line)
        if let reply = autoReply?(line) { onLine?(reply) }
    }
    func simulateCrash() { onTerminate?() }
}

final class SidecarClientTests: XCTestCase {
    func testChatResolvesWithResultText() async throws {
        let transport = FakeTransport()
        transport.autoReply = { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String else { return nil }
            return #"{"kind":"result","id":"\#(id)","ok":true,"text":"you focused 2h"}"#
        }
        let client = SidecarClient(transport: transport)
        try client.start()
        let answer = try await client.chat("how was today?", threadId: "t1")
        XCTAssertEqual(answer, "you focused 2h")
        XCTAssertTrue(transport.sent.first?.contains("\"kind\":\"chat\"") == true)
    }

    func testCrashFailsPendingAndRestarts() async throws {
        let transport = FakeTransport()
        transport.autoReply = { _ in nil }  // never replies; we will crash instead
        let client = SidecarClient(transport: transport, restartDelay: 0)
        try client.start()
        XCTAssertEqual(transport.startCount, 1)

        let task = Task { try await client.chat("hi", threadId: "t1") }
        // Give the request a moment to register, then crash.
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.simulateCrash()

        do { _ = try await task.value; XCTFail("expected failure") }
        catch { /* pending request failed as expected */ }

        // Backoff is 0, so a restart should have happened.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertGreaterThanOrEqual(transport.startCount, 2)
    }
}
