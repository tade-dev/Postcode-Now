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
    ///
    /// This is a two-scenario test, deliberately: a handoff near the start
    /// of the loop (ring 0 barely left the centre, almost no opacity to
    /// donate) is compared against a handoff mid-travel (ring 0 fully
    /// visible, far from the lock radius). Asserting on only one handoff
    /// can't tell "the near-centre path works" from "every path looks like
    /// this regardless of handoff" — the two must read differently at the
    /// start, and still both resolve correctly by the end of the collapse.
    func testACollapseFromAnAlmostUnstartedScanStillTravelsInward() {
        let nearCentreHandoff = 0.01
        let midTravelHandoff = 0.5

        let nearCentreStart = RevealTimeline.sample(
            elapsed: 0,
            searchLoop: nearCentreHandoff,
            handoffLoop: nearCentreHandoff,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )
        let midTravelStart = RevealTimeline.sample(
            elapsed: 0,
            searchLoop: midTravelHandoff,
            handoffLoop: midTravelHandoff,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )

        // Premise: at the near-unstarted handoff, ring 0 (the unstaggered
        // ring, whose phase equals the global loop) really is close to the
        // centre and nearly invisible at the moment the fix lands — well
        // below the brightness of a ring caught mid-travel.
        XCTAssertLessThan(
            nearCentreStart.rings[0].opacity, 0.05,
            "a ring 1% into the loop should barely have faded in"
        )
        XCTAssertGreaterThan(
            midTravelStart.rings[0].opacity, 0.2,
            "a ring halfway through the loop should be fully visible"
        )

        // And it genuinely has almost nowhere to travel: starting a few
        // points off the lock radius, not tens of points off it the way
        // the mid-travel ring does. This is the thing the two scenarios
        // must disagree about, so a bug that ignores handoffLoop (e.g.
        // always freezing from loop 0, or from searchLoop instead) would
        // make these two numbers collapse to the same value and fail here.
        let nearCentreTravel = nearCentreStart.rings[0].radius - RevealTiming.lockRadius
        let midTravelTravel = midTravelStart.rings[0].radius - RevealTiming.lockRadius
        XCTAssertLessThan(nearCentreTravel, 10, "near-centre ring should start close to the lock radius")
        XCTAssertGreaterThan(midTravelTravel, 30, "mid-travel ring should start far from the lock radius")

        // The lock ring doesn't know or care how little the scan ring had
        // to donate — it still has to rise from ~0 to ~1 over the collapse,
        // which is exactly what carries the moment when the scan ring (the
        // near-centre case) had almost no opacity of its own to fade out of.
        let nearCentreEnd = RevealTimeline.sample(
            elapsed: RevealTiming.collapse,
            searchLoop: nearCentreHandoff,
            handoffLoop: nearCentreHandoff,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )
        for index in nearCentreStart.rings.indices {
            XCTAssertEqual(
                nearCentreEnd.rings[index].radius,
                RevealTiming.lockRadius,
                accuracy: 0.001,
                "ring \(index) did not arrive at the lock radius"
            )
        }
        XCTAssertLessThan(nearCentreStart.lockOpacity, 0.01, "the lock should not have appeared yet")
        XCTAssertGreaterThan(
            nearCentreEnd.lockOpacity, 0.95,
            "the lock ring must carry full opacity by the end of the collapse"
        )
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

final class HapticCueTests: XCTestCase {
    func testOneLockPlusOnePerCharacter() {
        let cues = RevealTimeline.hapticCues(outcodeCount: 2, incodeCount: 3)
        XCTAssertEqual(cues.count, 6)
        XCTAssertEqual(cues.first?.style, .rigid)
        XCTAssertEqual(cues.dropFirst().filter { $0.style == .soft }.count, 5)
    }

    func testCuesAreStrictlyOrdered() {
        for outcodeCount in 2...4 {
            let cues = RevealTimeline.hapticCues(outcodeCount: outcodeCount, incodeCount: 3)
            for pair in zip(cues, cues.dropFirst()) {
                XCTAssertLessThan(pair.0.time, pair.1.time, "cues out of order")
            }
        }
    }

    func testEveryCueLandsInsideTheReveal() {
        for outcodeCount in 2...4 {
            let total = RevealTimeline.duration(outcodeCount: outcodeCount, incodeCount: 3)
            for cue in RevealTimeline.hapticCues(outcodeCount: outcodeCount, incodeCount: 3) {
                XCTAssertGreaterThanOrEqual(cue.time, 0)
                XCTAssertLessThanOrEqual(cue.time, total, "a cue would fire after the reveal ended")
            }
        }
    }

    func testTheLockFiresBeforeAnyCharacter() {
        let cues = RevealTimeline.hapticCues(outcodeCount: 2, incodeCount: 3)
        XCTAssertEqual(cues[0].time, RevealTiming.lockHaptic, accuracy: 0.0001)
        XCTAssertGreaterThan(cues[1].time, RevealTiming.bloomStart)
    }
}
