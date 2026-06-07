import XCTest
import SwiftUI
@testable import BogiApp

/// Regression tests for the launch-crash root cause: SwiftPM's generated `Bundle.module`
/// accessor hard-codes a dev build path and `fatalError`s when the app runs from anywhere
/// else (DMG / /Applications / Gatekeeper translocation). `BogiAsset` must resolve its
/// resource bundle from the real locations WITHOUT ever crashing.
final class BogiAssetTests: XCTestCase {

    private func makeBundleDir(in dir: URL, named name: String) throws {
        // A minimal valid bundle: a directory the loader will accept via Bundle(url:).
        let bundleURL = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
    }

    func testLocatesBundleInFirstMatchingSearchURL() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bogi-asset-\(UUID().uuidString)")
        let resources = tmp.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try makeBundleDir(in: resources, named: "Bogi_BogiApp.bundle")

        let found = BogiAsset.locateResourceBundle(
            searchURLs: [tmp, resources],   // tmp has no bundle, resources does
            bundleName: "Bogi_BogiApp.bundle"
        )
        XCTAssertNotNil(found, "should resolve the bundle from Contents/Resources")
    }

    func testRetrievesMascotFromFlatBundleAsShipped() throws {
        // Production shape: build-app.sh ships a FLAT Bogi_BogiApp.bundle (just mascot.png,
        // no Info.plist) inside Contents/Resources. Prove the resolved bundle can vend it.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bogi-asset-flat-\(UUID().uuidString)")
        let resources = tmp.appendingPathComponent("Contents/Resources")
        let bundleDir = resources.appendingPathComponent("Bogi_BogiApp.bundle")
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: bundleDir.appendingPathComponent("mascot.png"))
        defer { try? FileManager.default.removeItem(at: tmp) }

        let bundle = try XCTUnwrap(BogiAsset.locateResourceBundle(searchURLs: [resources]))
        XCTAssertNotNil(bundle.url(forResource: "mascot", withExtension: "png"),
                        "flat resource bundle must vend mascot.png")
    }

    func testReturnsNilWhenBundleAbsentInsteadOfCrashing() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bogi-asset-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Must NOT crash (the whole point — no Bundle.module fatalError path).
        let found = BogiAsset.locateResourceBundle(
            searchURLs: [tmp],
            bundleName: "Bogi_BogiApp.bundle"
        )
        XCTAssertNil(found)
    }

    func testMascotImageAlwaysResolves() {
        // Accessing the mascot must never crash, regardless of where the bundle is.
        _ = BogiAsset.mascot
    }
}
