import PlacodeCore
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

    private static func measuredWidth(_ text: String, size: Double) -> Double {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: size)
        let raw = (text as NSString).size(withAttributes: [.font: font]).width
        let tracking = HeroType.tracking * Double(max(text.count - 1, 0))
        return Double(raw) + tracking
    }
}
