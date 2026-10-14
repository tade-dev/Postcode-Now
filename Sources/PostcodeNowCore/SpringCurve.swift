import Foundation

/// Unit-step response for SwiftUI's `spring(response:dampingFraction:)`.
/// Stiffness uses ω = 2π / response. Underdamped peaks stay within the
/// settle spec (≤ 1.015) at the cookbook damping values.
enum SpringCurve {
    static func value(response: Double, dampingFraction: Double, time: Double) -> Double {
        guard time > 0, response > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        let zeta = dampingFraction
        if zeta >= 1 {
            let decay = exp(-omega * time)
            return 1 - decay * (1 + omega * time)
        }
        let damped = omega * sqrt(1 - zeta * zeta)
        let envelope = exp(-zeta * omega * time)
        let cosine = cos(damped * time)
        let sine = (zeta * omega / damped) * sin(damped * time)
        return 1 - envelope * (cosine + sine)
    }

    static func peak(response: Double, dampingFraction: Double, until: Double = 1.5) -> Double {
        var highest = 0.0
        var time = 0.0
        while time <= until {
            highest = max(highest, value(response: response, dampingFraction: dampingFraction, time: time))
            time += 0.002
        }
        return highest
    }

    /// First time the curve stays within `tolerance` of 1.
    static func settleTime(
        response: Double,
        dampingFraction: Double,
        tolerance: Double = 0.01
    ) -> Double {
        var time = 0.0
        var steadySteps = 0
        let step = 0.005
        let limit = max(response * 4, 0.2)
        while time <= limit {
            let sample = value(response: response, dampingFraction: dampingFraction, time: time)
            if abs(sample - 1) <= tolerance {
                steadySteps += 1
                if steadySteps >= 3 {
                    return max(0, time - 2 * step)
                }
            } else {
                steadySteps = 0
            }
            time += step
        }
        return limit
    }
}
