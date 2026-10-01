import Foundation

/// Durations from MOTION.md. The wash runs in parallel with the postcode settle.
public enum MotionTiming {
    public static let locateChromeOut: Double = 0.10
    public static let outcode: Double = 0.12
    public static let beat: Double = 0.05
    public static let incode: Double = 0.14
    public static let incodeResponse: Double = 0.28
    public static let incodeDamping: Double = 0.92
    public static let wash: Double = 0.32
    public static let placeLabelDelay: Double = 0.10
    public static let placeLabel: Double = 0.18
    public static let cta: Double = 0.18
    public static let ctaResponse: Double = 0.32
    public static let ctaDamping: Double = 0.88
    public static let scrimIn: Double = 0.18
    public static let scrimOut: Double = 0.16
    public static let toastIn: Double = 0.16
    public static let toastHold: Double = 1.2
    public static let toastOut: Double = 0.14
    public static let banner: Double = 0.16
    public static let pulseLoop: Double = 1.0
    /// Opacity swing of the locate rings. MOTION.md caps amplitude at 12%.
    public static let pulseAmplitude: Double = 0.12
    public static let reduceMotionCrossfade: Double = 0.08

    public static var incodeDelay: Double { outcode + beat }
    public static var ctaDelay: Double { incodeDelay + incode }

    /// Sequential reveal plus the CTA spring coming to rest. Wash overlaps this.
    public static var signatureDuration: Double {
        ctaDelay + SpringCurve.settleTime(response: ctaResponse, dampingFraction: ctaDamping)
    }
}
