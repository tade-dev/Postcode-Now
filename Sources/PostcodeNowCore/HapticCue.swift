import Foundation

public enum HapticStyle: String, Equatable, Sendable {
    case rigid
    case soft
    case light
}

/// A haptic the reveal promises to fire at a known time. Declaring these in
/// the timeline rather than detecting them in a view makes their order,
/// count and bounds testable.
public struct HapticCue: Equatable, Sendable {
    public var time: Double
    public var style: HapticStyle

    public init(time: Double, style: HapticStyle) {
        self.time = time
        self.style = style
    }
}
