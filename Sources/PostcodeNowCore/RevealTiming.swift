import Foundation

/// Durations for the four-act reveal, measured in seconds from the instant
/// the location fix lands. See docs/superpowers/specs/2026-10-14-reveal-motion-design.md.
public enum RevealTiming {
    // MARK: Act 1 — searching (loops until the fix arrives)

    public static let scanLoop: Double = 1.6
    /// Phase offset between the three scan rings, as a fraction of the loop.
    public static let scanStagger: Double = 0.33
    public static let scanInnerRadius: Double = 36
    public static let scanOuterRadius: Double = 104
    public static let scanPeakOpacity: Double = 0.26
    public static let scanRingCount: Int = 3

    // MARK: Act 2 — the lock

    public static let collapse: Double = 0.28
    public static let lockHaptic: Double = 0.26
    public static let lockRadius: Double = 28
    public static let lockContracted: Double = 24
    public static let captionOut: Double = 0.18

    // MARK: Act 3 — the bloom

    public static let stretchStart: Double = 0.45
    public static let stretch: Double = 0.17
    public static let bloomStart: Double = 0.62
    /// Widened from 0.045 on purpose: it keeps the reveal inside its 1.4-1.8s
    /// band while short codes still settle before long ones, and spaces each
    /// character's haptic far enough apart (~125ms) to be felt separately.
    /// Do not round it back down.
    public static let characterStagger: Double = 0.125
    public static let beat: Double = 0.05
    public static let characterResponse: Double = 0.30
    public static let characterDamping: Double = 0.80
    /// How long after a character starts moving before it reads as landed.
    public static let characterLand: Double = 0.15
    public static let lineDissolveStart: Double = 0.95
    public static let lineDissolve: Double = 0.25

    // MARK: Act 4 — the wash

    public static let washStart: Double = 0.70
    public static let wash: Double = 0.50
    public static let labelStart: Double = 1.05
    public static let label: Double = 0.25
    public static let bannerStart: Double = 0.70
    public static let banner: Double = 0.20

    // MARK: The CTA, which always follows the last character

    public static let ctaResponse: Double = 0.32
    public static let ctaDamping: Double = 0.88
    /// The CTA starts slightly before the code finishes settling, so the
    /// screen never reads as empty between the two.
    public static let ctaOverlap: Double = 0.15
    public static let ctaFloor: Double = 1.0

    // MARK: Derived

    /// When character `index` begins its spring. The incode waits one beat
    /// after the outcode, which is what makes the code read in two halves.
    public static func characterStart(index: Int, outcodeCount: Int) -> Double {
        let staggered = bloomStart + characterStagger * Double(index)
        return index < outcodeCount ? staggered : staggered + beat
    }

    public static func charactersSettled(outcodeCount: Int, incodeCount: Int) -> Double {
        let last = max(0, outcodeCount + incodeCount - 1)
        let start = characterStart(index: last, outcodeCount: outcodeCount)
        return start + SpringCurve.settleTime(
            response: characterResponse,
            dampingFraction: characterDamping
        )
    }

    public static func ctaStart(outcodeCount: Int, incodeCount: Int) -> Double {
        let settled = charactersSettled(outcodeCount: outcodeCount, incodeCount: incodeCount)
        return max(ctaFloor, settled - ctaOverlap)
    }

    public static func duration(outcodeCount: Int, incodeCount: Int) -> Double {
        ctaStart(outcodeCount: outcodeCount, incodeCount: incodeCount)
            + SpringCurve.settleTime(response: ctaResponse, dampingFraction: ctaDamping)
    }
}
