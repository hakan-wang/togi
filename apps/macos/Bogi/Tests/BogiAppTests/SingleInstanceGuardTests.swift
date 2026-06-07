import XCTest
@testable import BogiApp

final class SingleInstanceGuardTests: XCTestCase {
    private func tempLockPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bogi-test-\(UUID().uuidString).lock").path
    }

    func testAcquireSucceedsOnFreshPath() {
        let path = tempLockPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertTrue(SingleInstanceGuard.acquire(lockPath: path))
    }

    func testSecondHolderIsBlockedWhileFirstHoldsLock() {
        let path = tempLockPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Simulate the "other instance" holding the lock with its own fd, mirroring
        // exactly what SingleInstanceGuard.acquire does internally.
        let firstFD = open(path, O_CREAT | O_RDWR, 0o644)
        XCTAssertGreaterThanOrEqual(firstFD, 0)
        XCTAssertEqual(flock(firstFD, LOCK_EX | LOCK_NB), 0, "first holder should win")

        // A duplicate attempting to acquire the same path must be rejected.
        XCTAssertFalse(SingleInstanceGuard.acquire(lockPath: path))

        // Releasing the first holder frees the lock again.
        flock(firstFD, LOCK_UN)
        close(firstFD)
        XCTAssertTrue(SingleInstanceGuard.acquire(lockPath: path))
    }

    func testAcquireFailsOpenOnUnwritablePath() {
        // A path under a non-existent, uncreatable directory: open() fails, and we must
        // fail open (return true) rather than block launch over a filesystem quirk.
        XCTAssertTrue(SingleInstanceGuard.acquire(lockPath: "/nonexistent-dir-xyz/.lock"))
    }

    func testIsTestEnvironmentDetectedUnderXCTest() {
        XCTAssertTrue(SingleInstanceGuard.isTestOrDemoEnvironment())
    }
}
