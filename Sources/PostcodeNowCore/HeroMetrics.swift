import Foundation

/// Arithmetic shared by whole-string measurement and per-character layout.
/// Keeping it here, with no UIKit, is what lets the invariant that the two
/// agree be a test rather than a hope.
public enum HeroMetrics {
    /// Tracking sits between characters, so n glyphs have n - 1 gaps.
    public static func totalWidth(advances: [Double], tracking: Double) -> Double {
        guard !advances.isEmpty else { return 0 }
        return advances.reduce(0, +) + tracking * Double(advances.count - 1)
    }

    /// Leading edge of each character, relative to the string's leading edge.
    public static func offsets(advances: [Double], tracking: Double) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(advances.count)
        var cursor = 0.0
        for advance in advances {
            result.append(cursor)
            cursor += advance + tracking
        }
        return result
    }
}
