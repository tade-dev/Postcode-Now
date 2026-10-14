import Foundation
import XCTest
@testable import PostcodeNowCore

final class HeroMetricsTests: XCTestCase {
    func testTotalWidthIsAdvancesPlusTrackingBetweenThem() {
        let advances = [10.0, 20.0, 30.0]
        // Tracking sits between characters, so three glyphs have two gaps.
        XCTAssertEqual(
            HeroMetrics.totalWidth(advances: advances, tracking: 2),
            64,
            accuracy: 0.0001
        )
    }

    func testSingleCharacterHasNoTracking() {
        XCTAssertEqual(
            HeroMetrics.totalWidth(advances: [42], tracking: 5),
            42,
            accuracy: 0.0001
        )
    }

    func testEmptyIsZero() {
        XCTAssertEqual(HeroMetrics.totalWidth(advances: [], tracking: 5), 0, accuracy: 0.0001)
    }

    func testOffsetsStartAtZeroAndAccumulate() {
        let offsets = HeroMetrics.offsets(advances: [10, 20, 30], tracking: 2)
        XCTAssertEqual(offsets, [0, 12, 34])
    }

    /// The invariant that keeps per-character layout agreeing with the width
    /// HeroFitting measured for the whole string.
    func testLastOffsetPlusLastAdvanceEqualsTotalWidth() {
        let advances = [11.5, 9.25, 30.0, 14.75, 8.0]
        let tracking = HeroType.tracking
        let offsets = HeroMetrics.offsets(advances: advances, tracking: tracking)
        XCTAssertEqual(
            offsets.last! + advances.last!,
            HeroMetrics.totalWidth(advances: advances, tracking: tracking),
            accuracy: 0.0001
        )
    }

    /// Review Focus 3: GIR 0AA is seven characters with a three-letter
    /// outcode, and it must lay out like any other postcode.
    func testGiroLaysOutAsSevenCharacters() {
        let advances = Array(repeating: 40.0, count: 7)
        let offsets = HeroMetrics.offsets(advances: advances, tracking: HeroType.tracking)
        XCTAssertEqual(offsets.count, 7)
        XCTAssertEqual(
            offsets.last! + 40.0,
            HeroMetrics.totalWidth(advances: advances, tracking: HeroType.tracking),
            accuracy: 0.0001
        )
    }
}
