import Foundation
import XCTest
@testable import PostcodeNowCore

final class RevealTimingTests: XCTestCase {
    func testActBoundariesAreOrdered() {
        XCTAssertEqual(RevealTiming.collapse, 0.28)
        XCTAssertEqual(RevealTiming.lockHaptic, 0.26)
        XCTAssertEqual(RevealTiming.stretchStart, 0.45)
        XCTAssertEqual(RevealTiming.bloomStart, 0.62)
        XCTAssertEqual(RevealTiming.washStart, 0.70)

        XCTAssertLessThan(RevealTiming.lockHaptic, RevealTiming.collapse)
        XCTAssertLessThan(RevealTiming.collapse, RevealTiming.stretchStart)
        XCTAssertEqual(
            RevealTiming.stretchStart + RevealTiming.stretch,
            RevealTiming.bloomStart,
            accuracy: 0.0001
        )
        XCTAssertLessThan(RevealTiming.bloomStart, RevealTiming.washStart)
    }

    func testCharacterStartsStaggerAndTakeABeatAfterTheOutcode() {
        // "M1 1AE" -> outcode 2, incode 3.
        let first = RevealTiming.characterStart(index: 0, outcodeCount: 2)
        let second = RevealTiming.characterStart(index: 1, outcodeCount: 2)
        let third = RevealTiming.characterStart(index: 2, outcodeCount: 2)

        XCTAssertEqual(first, RevealTiming.bloomStart, accuracy: 0.0001)
        XCTAssertEqual(second - first, RevealTiming.characterStagger, accuracy: 0.0001)
        // The first incode character waits an extra beat.
        XCTAssertEqual(
            third - second,
            RevealTiming.characterStagger + RevealTiming.beat,
            accuracy: 0.0001
        )
    }

    func testCTAWaitsForTheLastCharacter() {
        let shortCode = RevealTiming.ctaStart(outcodeCount: 2, incodeCount: 3)
        let longCode = RevealTiming.ctaStart(outcodeCount: 4, incodeCount: 3)
        XCTAssertLessThan(shortCode, longCode)
        XCTAssertGreaterThanOrEqual(shortCode, RevealTiming.ctaFloor)
    }

    func testDurationStaysInsideTheBudgetForEveryPostcodeShape() {
        // Valid UK hero strings run 5 to 7 characters: A9 9AA up to AA9A 9AA.
        for outcodeCount in 2...4 {
            let total = RevealTiming.duration(outcodeCount: outcodeCount, incodeCount: 3)
            XCTAssertGreaterThanOrEqual(total, 1.4, "too fast at outcode \(outcodeCount)")
            XCTAssertLessThanOrEqual(total, 1.8, "too slow at outcode \(outcodeCount)")
        }
    }

    func testSpringsDoNotOvershootTheHouseLimit() {
        XCTAssertLessThanOrEqual(
            SpringCurve.peak(
                response: RevealTiming.characterResponse,
                dampingFraction: RevealTiming.characterDamping
            ),
            1.06
        )
        XCTAssertLessThanOrEqual(
            SpringCurve.peak(
                response: RevealTiming.ctaResponse,
                dampingFraction: RevealTiming.ctaDamping
            ),
            1.015
        )
    }

    func testEasingCurvesAreAnchored() {
        XCTAssertEqual(Easing.easeInCubic(0), 0, accuracy: 0.0001)
        XCTAssertEqual(Easing.easeInCubic(1), 1, accuracy: 0.0001)
        XCTAssertEqual(Easing.easeOutBack(0), 0, accuracy: 0.0001)
        XCTAssertEqual(Easing.easeOutBack(1), 1, accuracy: 0.0001)
        // easeOutBack overshoots on the way, which is the point of it.
        XCTAssertGreaterThan(Easing.easeOutBack(0.7), 1.0)
    }
}

final class RevealSampleTests: XCTestCase {
    func testSettledIsFullyResolved() {
        let settled = RevealSample.settled(outcodeCount: 2, incodeCount: 3)

        XCTAssertEqual(settled.characters.count, 5)
        for character in settled.characters {
            XCTAssertEqual(character.opacity, 1, accuracy: 0.0001)
            XCTAssertEqual(character.scale, 1, accuracy: 0.0001)
            XCTAssertEqual(character.offsetY, 0, accuracy: 0.0001)
        }
        XCTAssertEqual(settled.washProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.ctaOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.sectionOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.districtOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.bannerOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.captionOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(settled.lineOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(settled.lockOpacity, 0, accuracy: 0.0001)
        XCTAssertTrue(settled.rings.allSatisfy { $0.opacity == 0 })
    }

    func testSettledOutcodeCharactersAreBold() {
        let settled = RevealSample.settled(outcodeCount: 2, incodeCount: 3)
        XCTAssertEqual(settled.characters[0].weightBlend, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.characters[1].weightBlend, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.characters[4].weightBlend, 1, accuracy: 0.0001)
    }
}
