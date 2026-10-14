import Foundation
import XCTest
@testable import PostcodeNowCore

final class ScanTests: XCTestCase {
    func testScanProducesThreeStaggeredRings() {
        let rings = RevealTimeline.scanRings(loop: 0)
        XCTAssertEqual(rings.count, RevealTiming.scanRingCount)
        // Staggered, so no two rings share a radius at any single moment.
        XCTAssertNotEqual(rings[0].radius, rings[1].radius)
        XCTAssertNotEqual(rings[1].radius, rings[2].radius)
    }

    func testRingsTravelOutwardAndStayInsideTheirBounds() {
        for step in 0...200 {
            let loop = Double(step) / 200
            for ring in RevealTimeline.scanRings(loop: loop) {
                XCTAssertGreaterThanOrEqual(ring.radius, RevealTiming.scanInnerRadius - 0.001)
                XCTAssertLessThanOrEqual(ring.radius, RevealTiming.scanOuterRadius + 0.001)
                XCTAssertGreaterThanOrEqual(ring.opacity, 0)
                XCTAssertLessThanOrEqual(ring.opacity, RevealTiming.scanPeakOpacity + 0.001)
            }
        }
    }

    func testScanIsSeamlessAcrossTheLoopBoundary() {
        let before = RevealTimeline.scanRings(loop: 0.999)
        let after = RevealTimeline.scanRings(loop: 0.0)
        // Only the unstaggered ring (index 0, offset 0) has its own phase
        // wrap coincide with this global loop value wrapping from 0.999 to
        // 0.0 — the other two rings are 0.33 and 0.66 through their own
        // cycle at that instant and are legitimately mid-travel (bright).
        // A ring at the end of its travel has faded out, so wrapping it
        // back to the centre must not be visible.
        XCTAssertLessThan(before[0].opacity, 0.02)
        XCTAssertLessThan(after[0].opacity, 0.02)
    }

    func testRingsFadeInFromTheCentreAndOutAtTheEdge() {
        let rings = RevealTimeline.scanRings(loop: 0.0)
        XCTAssertLessThan(rings[0].opacity, 0.02, "a ring at the centre has not faded in yet")

        let midway = RevealTimeline.scanRings(loop: 0.4)
        XCTAssertGreaterThan(midway[0].opacity, 0.05, "a ring mid-travel should be visible")
    }
}

final class HandoffTests: XCTestCase {
    /// The test this redesign exists for. If the rings jump at elapsed = 0,
    /// the user sees a cut and the whole premise fails.
    func testRingsAtElapsedZeroMatchTheScanTheyHandedOffFrom() {
        for step in 0...100 {
            let handoff = Double(step) / 100
            let scanning = RevealTimeline.scanRings(loop: handoff)
            let revealing = RevealTimeline.sample(
                elapsed: 0,
                searchLoop: handoff,
                handoffLoop: handoff,
                outcodeCount: 2,
                incodeCount: 3,
                reduceMotion: false
            )

            for index in scanning.indices {
                XCTAssertEqual(
                    revealing.rings[index].radius,
                    scanning[index].radius,
                    accuracy: 0.0001,
                    "radius jumped at handoffLoop \(handoff), ring \(index)"
                )
                XCTAssertEqual(
                    revealing.rings[index].opacity,
                    scanning[index].opacity,
                    accuracy: 0.0001,
                    "opacity jumped at handoffLoop \(handoff), ring \(index)"
                )
            }
        }
    }

    /// Review Focus 1: a cached fix returns in ~50ms, so the rings are still
    /// near the centre when the collapse starts. It must still read as a
    /// collapse inward, not as rings appearing from nowhere.
    func testACollapseFromAnAlmostUnstartedScanStillTravelsInward() {
        let handoff = 0.01
        let atStart = RevealTimeline.sample(
            elapsed: 0,
            searchLoop: handoff,
            handoffLoop: handoff,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )
        let atEnd = RevealTimeline.sample(
            elapsed: RevealTiming.collapse,
            searchLoop: handoff,
            handoffLoop: handoff,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )

        for index in atStart.rings.indices {
            XCTAssertEqual(
                atEnd.rings[index].radius,
                RevealTiming.lockRadius,
                accuracy: 0.001,
                "ring \(index) did not arrive at the lock radius"
            )
        }
        // The lock ring must carry the moment when the scan rings had no
        // opacity to donate.
        XCTAssertGreaterThan(atEnd.lockOpacity, 0.5)
        XCTAssertLessThan(atStart.lockOpacity, atEnd.lockOpacity)
    }

    func testSearchingBranchIgnoresHandoffEntirely() {
        let a = RevealTimeline.sample(
            elapsed: nil,
            searchLoop: 0.3,
            handoffLoop: 0.0,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )
        let b = RevealTimeline.sample(
            elapsed: nil,
            searchLoop: 0.3,
            handoffLoop: 0.9,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.captionOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(a.washProgress, 0, accuracy: 0.0001)
        XCTAssertTrue(a.characters.allSatisfy { $0.opacity == 0 })
    }

    func testReduceMotionIsAlwaysSettledEvenWhileSearching() {
        let settled = RevealSample.settled(outcodeCount: 2, incodeCount: 3)
        for elapsed in [nil, 0, 0.3, 0.9, 99.0] as [Double?] {
            XCTAssertEqual(
                RevealTimeline.sample(
                    elapsed: elapsed,
                    searchLoop: 0.5,
                    handoffLoop: 0.5,
                    outcodeCount: 2,
                    incodeCount: 3,
                    reduceMotion: true
                ),
                settled
            )
        }
    }
}

final class BloomAndWashTests: XCTestCase {
    private func sample(at elapsed: Double) -> RevealSample {
        RevealTimeline.sample(
            elapsed: elapsed,
            searchLoop: 0.5,
            handoffLoop: 0.5,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )
    }

    func testTheLineStretchesOutOfTheLockBeforeAnyCharacterMoves() {
        let beforeStretch = sample(at: RevealTiming.stretchStart - 0.01)
        XCTAssertEqual(beforeStretch.lineLength, 0, accuracy: 0.001)

        let stretched = sample(at: RevealTiming.bloomStart)
        XCTAssertEqual(stretched.lineLength, 1, accuracy: 0.01)
        XCTAssertGreaterThan(stretched.lineOpacity, 0.5)

        // Nothing has bloomed yet at the instant the line completes.
        XCTAssertEqual(stretched.characters[0].opacity, 0, accuracy: 0.02)
    }

    func testCharactersArriveInOrderWithABeatBetweenTheHalves() {
        let justAfterFirst = sample(at: RevealTiming.bloomStart + 0.03)
        XCTAssertGreaterThan(justAfterFirst.characters[0].opacity, 0)
        XCTAssertEqual(justAfterFirst.characters[4].opacity, 0, accuracy: 0.001)

        // Inside the beat, the outcode has started but the incode has not.
        let duringBeat = sample(
            at: RevealTiming.characterStart(index: 2, outcodeCount: 2) - 0.01
        )
        XCTAssertGreaterThan(duringBeat.characters[1].opacity, 0)
        XCTAssertEqual(duringBeat.characters[2].opacity, 0, accuracy: 0.001)
    }

    func testTheWashStartsAsTheFirstCharacterLandsNotBefore() {
        let beforeWash = sample(at: RevealTiming.washStart - 0.01)
        XCTAssertEqual(beforeWash.washProgress, 0, accuracy: 0.001)

        let washed = sample(at: RevealTiming.washStart + RevealTiming.wash)
        XCTAssertEqual(washed.washProgress, 1, accuracy: 0.001)

        let halfway = sample(at: RevealTiming.washStart + RevealTiming.wash / 2)
        XCTAssertEqual(halfway.washProgress, 0.5, accuracy: 0.02)
    }

    func testTheLineDissolvesOnceTheCodeIsThere() {
        let dissolved = sample(
            at: RevealTiming.lineDissolveStart + RevealTiming.lineDissolve
        )
        XCTAssertEqual(dissolved.lineOpacity, 0, accuracy: 0.001)
    }

    func testTheCTAIsLast() {
        let ctaStart = RevealTiming.ctaStart(outcodeCount: 2, incodeCount: 3)
        XCTAssertEqual(sample(at: ctaStart - 0.01).ctaOpacity, 0, accuracy: 0.001)
        XCTAssertGreaterThan(sample(at: ctaStart + 0.2).ctaOpacity, 0.5)
    }

    func testEverythingLandsExactlySettledAtDuration() {
        let total = RevealTimeline.duration(outcodeCount: 2, incodeCount: 3)
        let settled = RevealSample.settled(outcodeCount: 2, incodeCount: 3)

        XCTAssertEqual(sample(at: total), settled)
        XCTAssertEqual(sample(at: total + 10), settled)
    }

    func testEveryFieldStaysInRangeAcrossTheWholeReveal() {
        let total = RevealTimeline.duration(outcodeCount: 4, incodeCount: 3)
        var time = 0.0
        while time <= total + 0.1 {
            let frame = RevealTimeline.sample(
                elapsed: time,
                searchLoop: 0.5,
                handoffLoop: 0.5,
                outcodeCount: 4,
                incodeCount: 3,
                reduceMotion: false
            )
            for value in [
                frame.lockOpacity, frame.lineOpacity, frame.lineLength,
                frame.washProgress, frame.captionOpacity, frame.wordmarkOpacity,
                frame.sectionOpacity, frame.districtOpacity, frame.ctaOpacity,
                frame.bannerOpacity,
            ] {
                XCTAssertGreaterThanOrEqual(value, 0, "negative at t=\(time)")
                XCTAssertLessThanOrEqual(value, 1, "above 1 at t=\(time)")
            }
            for character in frame.characters {
                XCTAssertGreaterThanOrEqual(character.opacity, 0, "t=\(time)")
                XCTAssertLessThanOrEqual(character.opacity, 1, "t=\(time)")
                XCTAssertGreaterThan(character.scale, 0, "a zero scale collapses the glyph at t=\(time)")
                XCTAssertLessThanOrEqual(character.scale, 1.1, "t=\(time)")
            }
            time += 0.001
        }
    }

    func testOpacitiesOnlyEverIncrease() {
        let total = RevealTimeline.duration(outcodeCount: 2, incodeCount: 3)
        var previous = sample(at: 0)
        var time = 0.001
        while time <= total {
            let frame = sample(at: time)
            XCTAssertGreaterThanOrEqual(
                frame.washProgress, previous.washProgress - 0.0001, "wash reversed at t=\(time)"
            )
            XCTAssertGreaterThanOrEqual(
                frame.ctaOpacity, previous.ctaOpacity - 0.0001, "cta reversed at t=\(time)"
            )
            XCTAssertLessThanOrEqual(
                frame.captionOpacity, previous.captionOpacity + 0.0001, "caption returned at t=\(time)"
            )
            previous = frame
            time += 0.001
        }
    }
}
