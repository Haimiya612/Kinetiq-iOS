import XCTest
@testable import Kinetiq

final class TaglineSelectorTests: XCTestCase {
    func testSelectionDoesNotRepeatPreviousTagline() {
        let options = ["One", "Two", "Three"]
        let selected = TaglineSelector.next(
            previous: "Two",
            candidates: options,
            choose: { $0.last }
        )

        XCTAssertEqual(selected, "Three")
        XCTAssertNotEqual(selected, "Two")
    }

    func testSingleCandidateCanBeSelectedAgain() {
        let selected = TaglineSelector.next(
            previous: "Only",
            candidates: ["Only"],
            choose: { $0.first }
        )

        XCTAssertEqual(selected, "Only")
    }

    func testEmptyCandidateListUsesBrandFallback() {
        let selected = TaglineSelector.next(
            previous: nil,
            candidates: [],
            choose: { _ in nil }
        )

        XCTAssertEqual(selected, BrandTagline.options[0])
    }
}
