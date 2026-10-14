import Foundation

/// Durations for everything that is not the reveal itself. The reveal's own
/// timings live in RevealTiming.
public enum MotionTiming {
    public static let scrimIn: Double = 0.18
    public static let scrimOut: Double = 0.16
    public static let toastIn: Double = 0.16
    public static let toastHold: Double = 1.2
    public static let toastOut: Double = 0.14
    public static let reduceMotionCrossfade: Double = 0.08
    /// How long the tap-to-skip crossfade takes. Short enough to feel like a
    /// skip, long enough not to read as a glitch.
    public static let skipCrossfade: Double = 0.12
    /// Edge screens (permission, failure, unsupported) entering and swapping.
    public static let edgeIn: Double = 0.24
    public static let edgeStagger: Double = 0.05
    public static let edgeCrossfade: Double = 0.20
}
