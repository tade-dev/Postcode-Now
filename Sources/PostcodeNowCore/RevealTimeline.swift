import Foundation

/// The whole reveal as a pure function of time. Views render what this
/// returns and decide nothing themselves.
///
/// Two clocks, deliberately. Act 1 loops for as long as the fix takes, so
/// folding it into one monotonic scalar would let that scalar grow without
/// bound. `searchLoop` is a 0...1 phase; `elapsed` is nil until the fix lands
/// and then counts seconds from it. `handoffLoop` is `searchLoop` frozen at
/// that instant, which is what lets Act 2 start from where the rings actually
/// were instead of snapping to a canonical position.
public enum RevealTimeline {
    public static func duration(outcodeCount: Int, incodeCount: Int) -> Double {
        RevealTiming.duration(outcodeCount: outcodeCount, incodeCount: incodeCount)
    }

    /// Ring positions during Act 1, for a loop phase in 0...1.
    public static func scanRings(loop: Double) -> [RingState] {
        (0..<RevealTiming.scanRingCount).map { index in
            let offset = RevealTiming.scanStagger * Double(index)
            let phase = ((loop + offset).truncatingRemainder(dividingBy: 1) + 1)
                .truncatingRemainder(dividingBy: 1)
            return RingState(
                radius: RevealTiming.scanInnerRadius
                    + (RevealTiming.scanOuterRadius - RevealTiming.scanInnerRadius) * phase,
                opacity: scanOpacity(phase: phase),
                lineWidth: 1
            )
        }
    }

    /// Fades in off the centre and out at the edge, so the wrap from phase 1
    /// back to phase 0 happens while the ring is invisible.
    private static func scanOpacity(phase: Double) -> Double {
        let fadeIn = Easing.clamp01(phase / 0.18)
        let fadeOut = Easing.clamp01((1 - phase) / 0.34)
        return RevealTiming.scanPeakOpacity * fadeIn * fadeOut
    }

    public static func sample(
        elapsed: Double?,
        searchLoop: Double,
        handoffLoop: Double,
        outcodeCount: Int,
        incodeCount: Int,
        reduceMotion: Bool
    ) -> RevealSample {
        if reduceMotion {
            return .settled(outcodeCount: outcodeCount, incodeCount: incodeCount)
        }
        guard let elapsed else {
            return searching(searchLoop: searchLoop, characterCount: outcodeCount + incodeCount)
        }
        return revealing(
            elapsed: max(0, elapsed),
            handoffLoop: handoffLoop,
            outcodeCount: outcodeCount,
            incodeCount: incodeCount
        )
    }

    private static func searching(searchLoop: Double, characterCount: Int) -> RevealSample {
        RevealSample(
            rings: scanRings(loop: searchLoop),
            lockRadius: RevealTiming.lockRadius,
            lockOpacity: 0,
            lineLength: 0,
            lineThickness: 0,
            lineOpacity: 0,
            characters: Array(
                repeating: CharacterState(opacity: 0, offsetY: 0, scale: 0.9, weightBlend: 0),
                count: max(0, characterCount)
            ),
            washProgress: 0,
            captionOpacity: 1,
            wordmarkOpacity: 1,
            sectionOpacity: 0,
            districtOpacity: 0,
            districtOffset: 0,
            ctaOpacity: 0,
            ctaOffset: 0,
            bannerOpacity: 0
        )
    }

    /// Act 2 only in this task. Task 4 adds the bloom, the wash and the chrome.
    private static func revealing(
        elapsed: Double,
        handoffLoop: Double,
        outcodeCount: Int,
        incodeCount: Int
    ) -> RevealSample {
        let collapse = Easing.easeInOutCubic(
            Easing.unit(elapsed, start: 0, duration: RevealTiming.collapse)
        )
        let frozen = scanRings(loop: handoffLoop)
        let rings = frozen.map { ring in
            RingState(
                radius: ring.radius + (RevealTiming.lockRadius - ring.radius) * collapse,
                opacity: ring.opacity * (1 - collapse),
                lineWidth: ring.lineWidth
            )
        }

        var sample = searching(
            searchLoop: handoffLoop,
            characterCount: outcodeCount + incodeCount
        )
        sample.rings = rings
        sample.lockOpacity = collapse
        sample.lockRadius = RevealTiming.lockRadius
            + (RevealTiming.lockContracted - RevealTiming.lockRadius)
            * Easing.easeOutBack(
                Easing.unit(elapsed, start: RevealTiming.collapse, duration: 0.17)
            )
        sample.captionOpacity = 1 - Easing.easeOutCubic(
            Easing.unit(elapsed, start: 0, duration: RevealTiming.captionOut)
        )
        return sample
    }
}
