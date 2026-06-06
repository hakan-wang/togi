import XCTest
@testable import BogiApp

private final class FakeProvider: SnapshotProviding {
    var state: PermissionState = .granted
    var next: CaptureSnapshot?
    func permissionState() -> PermissionState { state }
    func snapshot() -> CaptureSnapshot? { next }
}

final class CaptureTests: XCTestCase {

    private func makeController(provider: FakeProvider, excludes: CaptureExcludes, db: DatabaseService)
        -> (CaptureController, ObservationStore) {
        let store = ObservationStore(database: db)
        let controller = CaptureController(
            provider: provider,
            store: store,
            excludes: excludes,
            pruner: RetentionPruner(database: db),
            settings: SettingsStore(database: db)
        )
        return (controller, store)
    }

    func testDiffDedupStoresOncePerChange() throws {
        let db = try DatabaseService(inMemory: true)
        let provider = FakeProvider()
        let (controller, store) = makeController(provider: provider, excludes: .makeDefault(), db: db)

        provider.next = CaptureSnapshot(activeApp: "Safari", bundleId: "com.apple.Safari",
                                        windowTitle: "Inbox", text: "hello", hasSecureField: false)
        XCTAssertTrue(controller.performTick())   // stored
        XCTAssertFalse(controller.performTick())  // identical → deduped
        XCTAssertEqual(store.count(), 1)

        provider.next = CaptureSnapshot(activeApp: "Safari", bundleId: "com.apple.Safari",
                                        windowTitle: "Inbox", text: "world", hasSecureField: false)
        XCTAssertTrue(controller.performTick())   // changed → stored
        XCTAssertEqual(store.count(), 2)
    }

    func testSecureFieldIsExcluded() throws {
        let db = try DatabaseService(inMemory: true)
        let provider = FakeProvider()
        let (controller, store) = makeController(provider: provider, excludes: .makeDefault(), db: db)

        provider.next = CaptureSnapshot(activeApp: "Safari", bundleId: "com.apple.Safari",
                                        windowTitle: "Login", text: "secret", hasSecureField: true)
        XCTAssertFalse(controller.performTick())
        XCTAssertEqual(store.count(), 0)
    }

    func testSensitiveBundleAndDomainExcluded() {
        let excludes = CaptureExcludes.makeDefault()
        let pwManager = CaptureSnapshot(activeApp: "1Password", bundleId: "com.1password.1password",
                                        windowTitle: "Vault", text: "", hasSecureField: false)
        XCTAssertTrue(excludes.isExcluded(pwManager))

        let bank = CaptureSnapshot(activeApp: "Safari", bundleId: "com.apple.Safari",
                                   windowTitle: "Internetbank", text: "internetbanken.swedbank.se balance",
                                   hasSecureField: false)
        XCTAssertTrue(excludes.isExcluded(bank))

        let normal = CaptureSnapshot(activeApp: "Notes", bundleId: "com.apple.Notes",
                                     windowTitle: "Ideas", text: "ship bogi", hasSecureField: false)
        XCTAssertFalse(excludes.isExcluded(normal))
    }

    func testPrivateWindowExcluded() {
        let excludes = CaptureExcludes.makeDefault()
        let priv = CaptureSnapshot(activeApp: "Safari", bundleId: "com.apple.Safari",
                                   windowTitle: "Start Page — Private", text: "x", hasSecureField: false)
        XCTAssertTrue(excludes.isExcluded(priv))
    }

    func testRetentionPrunesOldRows() throws {
        let db = try DatabaseService(inMemory: true)
        let store = ObservationStore(database: db)
        let now = Date()

        store.insert(ActivityObservation(id: "old", capturedAt: now.addingTimeInterval(-20 * 86_400),
                                         activeApp: nil, activeAppBundleId: nil, activeWindowTitle: nil,
                                         text: "old", contentHash: "a", captureMethod: "ax", excluded: false, focused: true))
        store.insert(ActivityObservation(id: "new", capturedAt: now.addingTimeInterval(-1 * 86_400),
                                         activeApp: nil, activeAppBundleId: nil, activeWindowTitle: nil,
                                         text: "new", contentHash: "b", captureMethod: "ax", excluded: false, focused: true))
        XCTAssertEqual(store.count(), 2)

        let deleted = RetentionPruner(database: db).prune(retentionDays: 14, now: now)
        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(store.count(), 1)
    }

    func testPausedDoesNotCapture() throws {
        let db = try DatabaseService(inMemory: true)
        let provider = FakeProvider()
        let (controller, store) = makeController(provider: provider, excludes: .makeDefault(), db: db)
        controller.isPaused = true
        provider.next = CaptureSnapshot(activeApp: "Notes", bundleId: "com.apple.Notes",
                                        windowTitle: "Ideas", text: "x", hasSecureField: false)
        XCTAssertFalse(controller.performTick())
        XCTAssertEqual(store.count(), 0)
    }
    func testSnapshotCarriesFocusedFlag() {
        let snap = CaptureSnapshot(
            activeApp: "Xcode", bundleId: "com.apple.dt.Xcode",
            windowTitle: "Bogi", text: "hello", hasSecureField: false
        )
        XCTAssertTrue(snap.focused, "captured snapshot is the focused window by default")
    }

    func testStoredObservationIsMarkedFocused() throws {
        let db = try DatabaseService(inMemory: true)
        let provider = FakeProvider()
        provider.next = CaptureSnapshot(
            activeApp: "Xcode", bundleId: "com.apple.dt.Xcode",
            windowTitle: "Bogi", text: "writing tests", hasSecureField: false)
        let (controller, store) = makeController(provider: provider, excludes: .makeDefault(), db: db)
        XCTAssertTrue(controller.performTick())
        let stored = store.recent(within: 3600)
        XCTAssertEqual(stored.first?.focused, true)
    }
}