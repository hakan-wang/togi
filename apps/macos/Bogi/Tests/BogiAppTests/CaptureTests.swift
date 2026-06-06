import XCTest
import GRDB
@testable import BogiApp

final class CaptureTests: XCTestCase {

    // MARK: - Helpers

    private func makeEnvironment() throws -> (DatabaseService, SettingsStore, ObservationStore) {
        let db = try DatabaseService(inMemory: true)
        return (db, SettingsStore(database: db), ObservationStore(database: db))
    }

    private func surface(
        app: String? = "Safari",
        bundle: String? = "com.apple.Safari",
        title: String? = "Some Page",
        domain: String? = nil,
        text: String = "hello world"
    ) -> CapturedSurface {
        CapturedSurface(
            activeApp: app,
            activeAppBundleId: bundle,
            windowTitle: title,
            domain: domain,
            rawText: text
        )
    }

    // MARK: - Text processor: clean / truncate / hash

    func testProcessorCleanCollapsesWhitespace() {
        let p = CaptureTextProcessor()
        XCTAssertEqual(p.clean("  hello\n\n   world \t"), "hello world")
        XCTAssertEqual(p.clean("\n\n  \t "), "")
    }

    func testProcessorTruncatesOnCharacterBoundary() {
        let p = CaptureTextProcessor(maxLength: 5)
        XCTAssertEqual(p.truncate("abcdefgh"), "abcde")
        XCTAssertEqual(p.truncate("ab"), "ab")
    }

    func testProcessorHashIsDeterministicAndContentSensitive() {
        let p = CaptureTextProcessor()
        XCTAssertEqual(p.hash("same"), p.hash("same"))
        XCTAssertNotEqual(p.hash("a"), p.hash("b"))
        // Known FNV-1a 64-bit value for the empty string seed.
        XCTAssertEqual(p.hash(""), "cbf29ce484222325")
    }

    func testProcessReturnsNilForEmptyText() {
        let p = CaptureTextProcessor()
        XCTAssertNil(p.process("   \n  "))
        XCTAssertNotNil(p.process("real text"))
    }

    // MARK: - Diff dedup

    func testShouldPersistSkipsUnchangedHash() {
        let p = CaptureTextProcessor()
        XCTAssertTrue(p.shouldPersist(newHash: "a", previousHash: nil))
        XCTAssertTrue(p.shouldPersist(newHash: "a", previousHash: "b"))
        XCTAssertFalse(p.shouldPersist(newHash: "a", previousHash: "a"))
    }

    func testDecideSkipsUnchangedSnapshot() throws {
        let (_, settings, store) = try makeEnvironment()
        let service = AccessibilityCaptureService(store: store, settings: settings)
        let s = surface(text: "writing the design doc")

        let first = service.decide(surface: s, previousHash: nil, now: Date(), id: "o1")
        guard case .capture(let obs) = first else {
            return XCTFail("expected first read to capture, got \(first)")
        }

        // Same content, now diffed against the just-persisted hash → skipped.
        let second = service.decide(surface: s, previousHash: obs.contentHash, now: Date(), id: "o2")
        XCTAssertTrue(second.isUnchanged)

        // Changed content → captured again.
        let third = service.decide(
            surface: surface(text: "now editing video"),
            previousHash: obs.contentHash, now: Date(), id: "o3"
        )
        if case .capture = third {} else { XCTFail("expected capture for changed content, got \(third)") }
    }

    func testApplyPersistsOnlyChangedSnapshots() throws {
        let (_, settings, store) = try makeEnvironment()
        var ids = ["a", "b", "c"].makeIterator()
        let service = AccessibilityCaptureService(
            store: store, settings: settings,
            now: { Date(timeIntervalSince1970: 1_000) },
            idProvider: { ids.next() ?? UUID().uuidString }
        )

        // First read persists.
        try service.apply(service.decide(surface: surface(text: "alpha"), previousHash: nil, now: Date(), id: "a"))
        let latest = try store.fetchLatest()
        XCTAssertEqual(try store.count(), 1)

        // Identical read is skipped.
        try service.apply(service.decide(surface: surface(text: "alpha"), previousHash: latest?.contentHash, now: Date(), id: "b"))
        XCTAssertEqual(try store.count(), 1)
    }

    func testDecideEmptyTextIsSkipped() throws {
        let (_, settings, store) = try makeEnvironment()
        let service = AccessibilityCaptureService(store: store, settings: settings)
        XCTAssertTrue(service.decide(surface: surface(text: "   "), previousHash: nil, now: Date(), id: "x").isEmpty)
    }

    // MARK: - Exclusion matching

    func testExcludesPasswordManagerByBundleId() {
        let ex = CaptureExcludes()
        XCTAssertTrue(ex.isExcluded(appBundleId: "com.1password.1password", windowTitle: "Vault", domain: nil))
        XCTAssertTrue(ex.isExcluded(appBundleId: "com.apple.SecurityAgent", windowTitle: nil, domain: nil))
        XCTAssertFalse(ex.isExcluded(appBundleId: "com.apple.Safari", windowTitle: "News", domain: "example.com"))
    }

    func testExcludesBankingDomainAndSubdomain() {
        let ex = CaptureExcludes()
        XCTAssertTrue(ex.isExcluded(appBundleId: "com.apple.Safari", windowTitle: nil, domain: "chase.com"))
        XCTAssertTrue(ex.isExcluded(appBundleId: "com.apple.Safari", windowTitle: nil, domain: "secure.chase.com"))
        // Look-alike domain must NOT match.
        XCTAssertFalse(ex.isExcluded(appBundleId: "com.apple.Safari", windowTitle: nil, domain: "notchase.com"))
    }

    func testExcludesIncognitoWindowByTitle() {
        let ex = CaptureExcludes()
        XCTAssertTrue(ex.isExcluded(appBundleId: "com.google.Chrome", windowTitle: "New Tab (Incognito)", domain: nil))
        XCTAssertTrue(ex.isExcluded(appBundleId: "org.mozilla.firefox", windowTitle: "Private Browsing", domain: nil))
        XCTAssertFalse(ex.isExcluded(appBundleId: "com.google.Chrome", windowTitle: "GitHub", domain: nil))
    }

    func testExcludesUserAddedAppAndDomain() {
        var ex = CaptureExcludes()
        ex.excludeApp(bundleId: "com.example.Journal")
        ex.excludeDomain("https://www.therapy-notes.com/app")
        XCTAssertTrue(ex.isExcluded(appBundleId: "com.example.Journal", windowTitle: nil, domain: nil))
        XCTAssertTrue(ex.isExcluded(appBundleId: nil, windowTitle: nil, domain: "therapy-notes.com"))

        ex.unexcludeApp(bundleId: "com.example.Journal")
        ex.unexcludeDomain("therapy-notes.com")
        XCTAssertFalse(ex.isExcluded(appBundleId: "com.example.Journal", windowTitle: nil, domain: nil))
        XCTAssertFalse(ex.isExcluded(appBundleId: nil, windowTitle: nil, domain: "therapy-notes.com"))
    }

    func testNormalizeDomainStripsSchemeWwwAndPath() {
        XCTAssertEqual(CaptureExcludes.normalizeDomain("https://www.Chase.com/login?x=1"), "chase.com")
        XCTAssertEqual(CaptureExcludes.normalizeDomain("WWW.Example.COM"), "example.com")
        XCTAssertNil(CaptureExcludes.normalizeDomain("   "))
    }

    func testDecideExcludedStoresMarkerWithoutTextAndDedups() throws {
        let (_, settings, store) = try makeEnvironment()
        let service = AccessibilityCaptureService(store: store, settings: settings)
        let pwSurface = surface(
            app: "1Password", bundle: "com.1password.1password",
            title: "My Secret Vault", domain: nil, text: "super secret password"
        )

        let decision = service.decide(surface: pwSurface, previousHash: nil, now: Date(), id: "e1")
        guard case .excluded(let marker) = decision else {
            return XCTFail("expected excluded, got \(decision)")
        }
        XCTAssertTrue(marker.excluded)
        XCTAssertNil(marker.text)              // no verbatim text stored
        XCTAssertNil(marker.activeWindowTitle) // title withheld too
        XCTAssertNotNil(marker.contentHash)

        // Consecutive excluded reads of the same app dedup.
        XCTAssertTrue(
            service.decide(surface: pwSurface, previousHash: marker.contentHash, now: Date(), id: "e2").isUnchanged
        )
    }

    // MARK: - Retention boundary

    func testCutoffComputation() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        XCTAssertEqual(RetentionPruner.cutoff(now: now, retentionDays: 14),
                       now.addingTimeInterval(-14 * 86_400))
        // Non-positive retention clamps to "now" (delete everything older than now).
        XCTAssertEqual(RetentionPruner.cutoff(now: now, retentionDays: 0), now)
        XCTAssertEqual(RetentionPruner.cutoff(now: now, retentionDays: -5), now)
    }

    func testShouldDeleteBoundaryIsStrictlyBefore() {
        let cutoff = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(RetentionPruner.shouldDelete(capturedAt: Date(timeIntervalSince1970: 999), cutoff: cutoff))
        XCTAssertFalse(RetentionPruner.shouldDelete(capturedAt: cutoff, cutoff: cutoff))               // at boundary: kept
        XCTAssertFalse(RetentionPruner.shouldDelete(capturedAt: Date(timeIntervalSince1970: 1_001), cutoff: cutoff))
    }

    func testPruneNowDeletesOnlyOutsideWindow() throws {
        let (db, settings, store) = try makeEnvironment()
        settings.set(.rawRetentionDays, "14")
        let now = Date(timeIntervalSince1970: 100 * 86_400)

        func makeObs(_ id: String, ageDays: Double) -> ActivityObservation {
            ActivityObservation(
                id: id, capturedAt: now.addingTimeInterval(-ageDays * 86_400),
                activeApp: "Safari", activeAppBundleId: "com.apple.Safari",
                activeWindowTitle: "t", text: "x", contentHash: "h\(id)",
                captureMethod: .ax, excluded: false
            )
        }
        try store.insert(makeObs("recent", ageDays: 1))    // within window → kept
        try store.insert(makeObs("edge", ageDays: 14))     // exactly at cutoff → kept
        try store.insert(makeObs("old", ageDays: 20))      // outside window → deleted

        let pruner = RetentionPruner(database: db, settings: settings, now: { now })
        let deleted = try pruner.pruneNow()
        XCTAssertEqual(deleted, 1)

        let remaining = Set(try store.fetchLast(10).map(\.id))
        XCTAssertEqual(remaining, ["recent", "edge"])
    }

    // MARK: - ObservationStore reads

    func testObservationStoreFetchLastAndInRange() throws {
        let (_, _, store) = try makeEnvironment()
        let base = Date(timeIntervalSince1970: 10_000)
        for i in 0..<5 {
            try store.insert(ActivityObservation(
                id: "o\(i)", capturedAt: base.addingTimeInterval(Double(i) * 6),
                activeApp: "App", activeAppBundleId: "com.app", activeWindowTitle: "t",
                text: "t\(i)", contentHash: "h\(i)", captureMethod: .ax, excluded: false
            ))
        }
        XCTAssertEqual(try store.count(), 5)

        // Newest first.
        XCTAssertEqual(try store.fetchLast(2).map(\.id), ["o4", "o3"])
        XCTAssertEqual(try store.fetchLatest()?.id, "o4")

        // Half-open range [base, base+18) → o0, o1, o2.
        let inRange = try store.fetchInRange(from: base, to: base.addingTimeInterval(18))
        XCTAssertEqual(inRange.map(\.id), ["o0", "o1", "o2"])
    }

    // MARK: - Window-title domain extraction

    func testDomainFromWindowTitle() {
        XCTAssertEqual(AccessibilityCaptureService.domain(fromWindowTitle: "Dashboard — app.chase.com"), "app.chase.com")
        XCTAssertNil(AccessibilityCaptureService.domain(fromWindowTitle: "Untitled Document"))
        XCTAssertNil(AccessibilityCaptureService.domain(fromWindowTitle: nil))
    }
}
