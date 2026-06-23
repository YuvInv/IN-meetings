import XCTest
@testable import INMeetingsCore

final class SplitLayoutTests: XCTestCase {
    func testFractionWithinRangeIsUnchanged() {
        // total 1000, mins 240/320 → legal range [0.24, 0.68]; 0.38 is inside.
        XCTAssertEqual(SplitLayout.clampFraction(0.38, total: 1000, min0: 240, min1: 320),
                       0.38, accuracy: 1e-9)
    }
    func testClampsBelowFirstMinimum() {
        XCTAssertEqual(SplitLayout.clampFraction(0.10, total: 1000, min0: 240, min1: 320),
                       0.24, accuracy: 1e-9)   // min0/usable
    }
    func testClampsAboveSecondMinimum() {
        XCTAssertEqual(SplitLayout.clampFraction(0.90, total: 1000, min0: 240, min1: 320),
                       0.68, accuracy: 1e-9)   // 1 - min1/usable
    }
    func testTooSmallToHonorBothMinsSplitsProportionally() {
        // usable 400 < 240+320 → proportional: 240/560.
        XCTAssertEqual(SplitLayout.clampFraction(0.50, total: 400, min0: 240, min1: 320),
                       240.0 / 560.0, accuracy: 1e-9)
    }
    func testNonFiniteFractionFallsBackToHalf() {
        XCTAssertEqual(SplitLayout.clampFraction(.nan, total: 1000, min0: 240, min1: 320),
                       0.5, accuracy: 1e-9)
    }
    func testZeroTotalIsSafe() {
        XCTAssertEqual(SplitLayout.clampFraction(0.38, total: 0, min0: 240, min1: 320),
                       0.5, accuracy: 1e-9)
    }
    func testDividerThicknessReducesUsableLength() {
        // usable = 1000 - 10 = 990; loFrac = 240/990.
        XCTAssertEqual(SplitLayout.clampFraction(0.0, total: 1000, min0: 240, min1: 320, divider: 10),
                       240.0 / 990.0, accuracy: 1e-9)
    }
    func testFirstLength() {
        XCTAssertEqual(SplitLayout.firstLength(fraction: 0.5, total: 1000), 500, accuracy: 1e-9)
        XCTAssertEqual(SplitLayout.firstLength(fraction: 0.5, total: 1000, divider: 10),
                       495, accuracy: 1e-9)
        XCTAssertEqual(SplitLayout.firstLength(fraction: 0.5, total: 0), 0, accuracy: 1e-9)
    }
    func testInfiniteFractionFallsBackToHalf() {
        XCTAssertEqual(SplitLayout.clampFraction(.infinity, total: 1000, min0: 240, min1: 320),
                       0.5, accuracy: 1e-9)
    }
    func testNegativeTotalIsSafe() {
        XCTAssertEqual(SplitLayout.clampFraction(0.38, total: -10, min0: 240, min1: 320),
                       0.5, accuracy: 1e-9)
    }
    func testNegativeMinimumStaysInUnitRange() {
        let f = SplitLayout.clampFraction(0.5, total: 1000, min0: -100, min1: 320)
        XCTAssertGreaterThanOrEqual(f, 0)
        XCTAssertLessThanOrEqual(f, 1)
    }
    func testFirstLengthClampsNegativeFractionToZero() {
        XCTAssertEqual(SplitLayout.firstLength(fraction: -0.1, total: 1000), 0, accuracy: 1e-9)
    }
}
