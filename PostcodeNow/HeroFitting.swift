import PostcodeNowCore
import UIKit

enum HeroFitting {
    static func pointSize(text: String, availableWidth: CGFloat, scaledPreference: CGFloat) -> CGFloat {
        let base = HeroType.basePointSize(characterCount: text.count)
        let preferred = min(HeroType.maxPointSize, Double(scaledPreference) * (base / 80))
        let width = measuredWidth(text, size: preferred)
        let fitted: Double
        if width > Double(availableWidth), width > 1 {
            fitted = preferred * Double(availableWidth) / width
        } else {
            fitted = preferred
        }
        return CGFloat(max(34, fitted))
    }

    /// Width of each character at this size, in order. Laying characters out
    /// from these keeps per-character rendering the same total width as the
    /// whole-string measurement `pointSize` fitted against.
    static func characterAdvances(text: String, size: CGFloat) -> [CGFloat] {
        let font = heroFont(size: Double(size))
        return text.map { character in
            (String(character) as NSString).size(withAttributes: [.font: font]).width
        }
    }

    private static func heroFont(size: Double) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Measures against the same unkerned per-character total the canvas
    /// actually draws, not the kerned whole-string width — the two differ
    /// because NSString's whole-string measurement applies pair kerning
    /// that per-character layout does not.
    private static func measuredWidth(_ text: String, size: Double) -> Double {
        let advances = characterAdvances(text: text, size: CGFloat(size)).map(Double.init)
        return HeroMetrics.totalWidth(advances: advances, tracking: HeroType.tracking)
    }
}
