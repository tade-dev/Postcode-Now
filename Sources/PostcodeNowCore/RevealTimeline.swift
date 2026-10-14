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

    private static func revealing(
        elapsed: Double,
        handoffLoop: Double,
        outcodeCount: Int,
        incodeCount: Int
    ) -> RevealSample {
        let count = max(0, outcodeCount + incodeCount)
        let total = RevealTiming.duration(outcodeCount: outcodeCount, incodeCount: incodeCount)
        if elapsed >= total {
            return .settled(outcodeCount: outcodeCount, incodeCount: incodeCount)
        }

        // Act 2 — the rings collapse from wherever they were into the lock.
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
        let contraction = Easing.easeOutBack(
            Easing.unit(elapsed, start: RevealTiming.collapse, duration: 0.17)
        )

        // Act 3 — the lock stretches into a line, then emits the characters.
        let stretch = Easing.easeInOutCubic(
            Easing.unit(elapsed, start: RevealTiming.stretchStart, duration: RevealTiming.stretch)
        )
        let lineFade = Easing.easeInCubic(
            Easing.unit(
                elapsed,
                start: RevealTiming.lineDissolveStart,
                duration: RevealTiming.lineDissolve
            )
        )
        let characters = (0..<count).map { index -> CharacterState in
            let start = RevealTiming.characterStart(index: index, outcodeCount: outcodeCount)
            let spring = Easing.clamp01(
                SpringCurve.value(
                    response: RevealTiming.characterResponse,
                    dampingFraction: RevealTiming.characterDamping,
                    time: elapsed - start
                )
            )
            return CharacterState(
                opacity: spring,
                offsetY: 14 * (1 - spring),
                scale: 0.86 + 0.14 * spring,
                weightBlend: spring
            )
        }

        // Act 4 — the colour the characters emit, then the labels and the CTA.
        let wash = Easing.easeInOutCubic(
            Easing.unit(elapsed, start: RevealTiming.washStart, duration: RevealTiming.wash)
        )
        let label = Easing.easeOutCubic(
            Easing.unit(elapsed, start: RevealTiming.labelStart, duration: RevealTiming.label)
        )
        let banner = Easing.easeOutCubic(
            Easing.unit(elapsed, start: RevealTiming.bannerStart, duration: RevealTiming.banner)
        )
        let cta = Easing.clamp01(
            SpringCurve.value(
                response: RevealTiming.ctaResponse,
                dampingFraction: RevealTiming.ctaDamping,
                time: elapsed - RevealTiming.ctaStart(
                    outcodeCount: outcodeCount,
                    incodeCount: incodeCount
                )
            )
        )

        return RevealSample(
            rings: rings,
            lockRadius: RevealTiming.lockRadius
                + (RevealTiming.lockContracted - RevealTiming.lockRadius) * contraction,
            lockOpacity: collapse * (1 - stretch),
            lineLength: stretch,
            lineThickness: 2 * stretch,
            lineOpacity: stretch * (1 - lineFade),
            characters: characters,
            washProgress: wash,
            captionOpacity: 1 - Easing.easeOutCubic(
                Easing.unit(elapsed, start: 0, duration: RevealTiming.captionOut)
            ),
            wordmarkOpacity: 1,
            sectionOpacity: label,
            districtOpacity: label,
            districtOffset: 3 * (1 - label),
            ctaOpacity: cta,
            ctaOffset: 10 * (1 - cta),
            bannerOpacity: banner
        )
    }

    /// One firm impact as the rings lock, then one soft impact as each
    /// character lands, so the code arrives in the hand as well as the eye.
    public static func hapticCues(outcodeCount: Int, incodeCount: Int) -> [HapticCue] {
        let count = max(0, outcodeCount + incodeCount)
        var cues = [HapticCue(time: RevealTiming.lockHaptic, style: .rigid)]
        for index in 0..<count {
            let start = RevealTiming.characterStart(index: index, outcodeCount: outcodeCount)
            cues.append(
                HapticCue(time: start + RevealTiming.characterLand, style: .soft)
            )
        }
        return cues
    }
}
