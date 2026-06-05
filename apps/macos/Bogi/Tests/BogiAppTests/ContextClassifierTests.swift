import XCTest
@testable import BogiApp

final class ContextClassifierTests: XCTestCase {
    func testClassifiesEditingFromKnownApps() {
        let classifier = ContextClassifier()
        let result = classifier.classify(activeApp: "Final Cut Pro", text: "timeline export")
        XCTAssertEqual(result.category, "video_editing")
        XCTAssertGreaterThan(result.confidence, 0.7)
    }
}
