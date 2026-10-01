import Foundation

enum Easing {
    static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    static func unit(_ time: Double, start: Double, duration: Double) -> Double {
        guard duration > 0 else { return time >= start ? 1 : 0 }
        return clamp01((time - start) / duration)
    }

    static func easeOutCubic(_ t: Double) -> Double {
        let x = clamp01(t)
        return 1 - pow(1 - x, 3)
    }

    static func easeInOutCubic(_ t: Double) -> Double {
        let x = clamp01(t)
        if x < 0.5 {
            return 4 * x * x * x
        }
        return 1 - pow(-2 * x + 2, 3) / 2
    }
}
