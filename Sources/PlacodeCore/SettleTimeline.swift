import Foundation

public struct SettleSample: Equatable, Sendable {
    public var locateOpacity: Double
    public var sectionOpacity: Double
    public var outcodeOpacity: Double
    public var outcodeScale: Double
    public var outcodeOffset: Double
    public var incodeOpacity: Double
    public var incodeScale: Double
    public var incodeWeight: Double
    public var placeOpacity: Double
    public var placeOffset: Double
    public var ctaOpacity: Double
    public var ctaOffset: Double
    public var wordmarkOpacity: Double
    public var bannerOpacity: Double
    public var wash: Double

    static let settled = SettleSample(
        locateOpacity: 0,
        sectionOpacity: 1,
        outcodeOpacity: 1,
        outcodeScale: 1,
        outcodeOffset: 0,
        incodeOpacity: 1,
        incodeScale: 1,
        incodeWeight: 1,
        placeOpacity: 1,
        placeOffset: 0,
        ctaOpacity: 1,
        ctaOffset: 0,
        wordmarkOpacity: 1,
        bannerOpacity: 1,
        wash: 1
    )
}

public enum SettleTimeline {
    public static var duration: Double { MotionTiming.signatureDuration }

    public static func sample(elapsed: Double, reduceMotion: Bool = false) -> SettleSample {
        if reduceMotion {
            return .settled
        }

        let outcodeProgress = Easing.easeOutCubic(
            Easing.unit(elapsed, start: 0, duration: MotionTiming.outcode)
        )
        let locateProgress = Easing.easeOutCubic(
            Easing.unit(elapsed, start: 0, duration: MotionTiming.locateChromeOut)
        )
        let wash = Easing.easeInOutCubic(
            Easing.unit(elapsed, start: 0, duration: MotionTiming.wash)
        )
        let placeProgress = Easing.easeOutCubic(
            Easing.unit(elapsed, start: MotionTiming.placeLabelDelay, duration: MotionTiming.placeLabel)
        )
        let incodeSpring = spring(
            response: MotionTiming.incodeResponse,
            damping: MotionTiming.incodeDamping,
            time: elapsed - MotionTiming.incodeDelay
        )
        let ctaSpring = spring(
            response: MotionTiming.ctaResponse,
            damping: MotionTiming.ctaDamping,
            time: elapsed - MotionTiming.ctaDelay
        )
        let bannerProgress = Easing.easeOutCubic(
            Easing.unit(elapsed, start: 0, duration: MotionTiming.banner)
        )
        let incodeUnit = Easing.clamp01(incodeSpring)
        let ctaUnit = Easing.clamp01(ctaSpring)

        return SettleSample(
            locateOpacity: 1 - locateProgress,
            sectionOpacity: outcodeProgress,
            outcodeOpacity: outcodeProgress,
            outcodeScale: 0.96 + 0.04 * outcodeProgress,
            outcodeOffset: 4 * (1 - outcodeProgress),
            incodeOpacity: incodeUnit,
            incodeScale: 0.96 + 0.04 * min(incodeSpring, 1.015),
            incodeWeight: incodeUnit,
            placeOpacity: placeProgress,
            placeOffset: 3 * (1 - placeProgress),
            ctaOpacity: ctaUnit,
            ctaOffset: 10 * (1 - ctaUnit),
            wordmarkOpacity: ctaUnit,
            bannerOpacity: bannerProgress,
            wash: wash
        )
    }

    private static func spring(response: Double, damping: Double, time: Double) -> Double {
        guard time > 0 else { return 0 }
        return SpringCurve.value(response: response, dampingFraction: damping, time: time)
    }
}
