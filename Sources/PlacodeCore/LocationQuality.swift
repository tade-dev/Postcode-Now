import Foundation

public enum LocationQuality: Equatable, Sendable {
    case precise
    case approximate
}

public enum LocationQualityRule {
    /// Fixes worse than this, or a reduced-accuracy authorization, use the weak-GPS state.
    public static let weakHorizontalAccuracyMeters: Double = 100

    public static func classify(horizontalAccuracy: Double, reducedAccuracy: Bool) -> LocationQuality {
        if reducedAccuracy {
            return .approximate
        }
        if !horizontalAccuracy.isFinite || horizontalAccuracy < 0 {
            return .approximate
        }
        if horizontalAccuracy > weakHorizontalAccuracyMeters {
            return .approximate
        }
        return .precise
    }
}
