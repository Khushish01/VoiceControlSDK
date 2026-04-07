import XCTest
@testable import VoiceControlSDK

final class LevenshteinDistanceTests: XCTestCase {

    func testIdenticalStrings() {
        XCTAssertEqual(LevenshteinDistance.distance("skandika", "skandika"), 0)
    }

    func testSingleSubstitution() {
        XCTAssertEqual(LevenshteinDistance.distance("scandika", "skandika"), 1)
    }

    func testSingleDeletion() {
        XCTAssertEqual(LevenshteinDistance.distance("skandka", "skandika"), 1)
    }

    func testMultipleEdits() {
        XCTAssertEqual(LevenshteinDistance.distance("scanica", "skandika"), 2)
    }

    func testEmptySource() {
        XCTAssertEqual(LevenshteinDistance.distance("", "skandika"), 8)
    }

    func testEmptyTarget() {
        XCTAssertEqual(LevenshteinDistance.distance("skandika", ""), 8)
    }

    func testBothEmpty() {
        XCTAssertEqual(LevenshteinDistance.distance("", ""), 0)
    }

    func testDistantWords() {
        let distance = LevenshteinDistance.distance("kaka", "skandika")
        XCTAssertTrue(distance > 3, "kaka should be too far from skandika for fuzzy match")
    }
}
