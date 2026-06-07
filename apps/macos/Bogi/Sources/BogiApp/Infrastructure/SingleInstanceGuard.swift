import AppKit

/// Guarantees at most one Togi process runs at a time.
///
/// Two instances are actively harmful here: each opens the same SQLite DB, spawns
/// its own Node sidecar, and runs a second capture loop. We enforce uniqueness with
/// a BSD advisory lock (`flock`) held for the whole process lifetime. The kernel
/// releases the lock automatically on exit/crash/`kill -9`, so there is no stale-lock
/// handling and no time-of-check/time-of-use race (unlike counting
/// `NSRunningApplication`). `NSRunningApplication` is used only to surface the
/// already-running instance for the user.
enum SingleInstanceGuard {
    /// The held lock. Kept open for the entire process lifetime — *not closing it is
    /// the point*: the open file descriptor is what holds the lock.
    private static var lockFD: Int32 = -1

    /// Posted by a duplicate launch so the live instance can surface its companion
    /// window ("Togi is already running"). Distributed (cross-process) — works because
    /// the app is not sandboxed.
    static let surfaceNotification = Notification.Name("sh.bogi.app.surfaceExisting")

    /// `~/Library/Application Support/Bogi/.singleton.lock`, alongside the database.
    /// Mirrors `DatabaseService.defaultPath()`'s directory (which also creates it).
    static func defaultLockPath() -> String {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Bogi", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".singleton.lock").path
    }

    /// Attempts to claim single-instance ownership.
    /// - Returns: `true` if this process is the primary (and now holds the lock);
    ///   `false` if another instance already holds it (caller should surface + exit).
    ///
    /// Fails open: if the lock file cannot be created (e.g. unwritable path), returns
    /// `true` so a filesystem quirk never prevents the app from launching.
    @discardableResult
    static func acquire(lockPath: String = defaultLockPath()) -> Bool {
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            lockFD = fd            // keep the fd open == keep the lock
            return true
        }
        close(fd)
        return false
    }

    /// Tells the already-running instance to surface itself, then quits this duplicate.
    /// Never returns. Uses `exit(0)` (not `NSApp.terminate`) so the duplicate dies
    /// early, before scenes/`NSApp` spin up and before any shared resource is touched.
    static func surfaceExistingInstanceAndExit() -> Never {
        let bundleID = Bundle.main.bundleIdentifier ?? "sh.bogi.app"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != .current }
        others.first?.activate(options: [.activateAllWindows])
        DistributedNotificationCenter.default().postNotificationName(
            surfaceNotification, object: nil, deliverImmediately: true)
        exit(0)
    }

    /// True when single-instance enforcement must be skipped: under XCTest (so unit
    /// tests never grab the real lock) or when explicitly opted out via
    /// `BOGI_ALLOW_MULTIPLE_INSTANCES=1` (dev/debug escape hatch).
    ///
    /// XCTest is detected by the presence of the XCTest runtime class — the real app
    /// never loads it. (`XCTestConfigurationFilePath` is set by Xcode's test host but
    /// not by the SwiftPM `swift test` runner, so it is not reliable on its own.)
    static func isTestOrDemoEnvironment() -> Bool {
        if ProcessInfo.processInfo.environment["BOGI_ALLOW_MULTIPLE_INSTANCES"] == "1" { return true }
        return NSClassFromString("XCTestCase") != nil
    }
}
