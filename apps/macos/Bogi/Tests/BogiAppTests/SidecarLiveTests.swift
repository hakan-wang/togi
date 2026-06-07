import XCTest
@testable import BogiApp

/// Manual, opt-in LIVE integration test that drives the REAL `ProcessSidecarTransport` +
/// `SidecarClient` against the bundled Node sidecar artifacts — the same path the app uses at
/// runtime, minus the launch gate. It catches a broken sidecar bundle (missing/unspawnable
/// `node`, a `main.cjs` that doesn't reach the `ready`/response handshake) that unit tests with
/// a fake transport can't.
///
///     BOGI_SIDECAR_LIVE=1 swift test --filter SidecarLiveTests
///
/// By default it points at the installed app's sidecar; override with BOGI_SIDECAR_DIR. It sends
/// one chat to a deliberately-unreachable backend, so it expects a fast ERROR frame (proving the
/// spawn + stdio round-trip works) rather than a real answer — and asserts it does NOT hang.
final class SidecarLiveTests: XCTestCase {
    func testRealSidecarSpawnsAndAnswersWithoutHanging() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BOGI_SIDECAR_LIVE"] == "1",
            "Set BOGI_SIDECAR_LIVE=1 to run the live sidecar spawn test."
        )
        let dir = ProcessInfo.processInfo.environment["BOGI_SIDECAR_DIR"]
            ?? "/Applications/Togi.app/Contents/Resources/sidecar"
        let side = URL(fileURLWithPath: dir)
        let node = side.appendingPathComponent("node")
        let script = side.appendingPathComponent("main.cjs")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: node.path), "bundled node missing/not executable")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path), "bundled main.cjs missing")

        let transport = ProcessSidecarTransport(
            nodeURL: node, scriptURL: script,
            environment: [
                "BOGI_BACKEND_URL": "https://127.0.0.1:9",   // refused fast → error frame, not a hang
                "BOGI_AUTH_TOKEN": "",
                "BOGI_DB_PATH": NSTemporaryDirectory() + "sidecar-live-test.db",
                "NODE_PATH": side.path,
            ])
        let client = SidecarClient(transport: transport, requestTimeout: 20)
        try client.start()
        XCTAssertTrue(transport.isRunning, "node process should be alive after start()")

        do {
            let reply = try await client.chat("hi", threadId: "live")
            // A reply (even empty) also proves the round-trip; we mainly assert it returned.
            XCTAssertNotNil(reply)
        } catch let error as SidecarError {
            // Expected: backend unreachable → remote error frame relayed back. NOT a timeout.
            if case .timedOut = error { XCTFail("sidecar hung — no response within the watchdog window") }
            if case .notRunning = error { XCTFail("sidecar process was not running") }
        }
        client.stop()
    }
}
