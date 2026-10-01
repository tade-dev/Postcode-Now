import Foundation

public struct RGB: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(hex: UInt32) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
    }

    var hex: UInt32 {
        (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
    }

    var relativeLuminance: Double {
        func channel(_ byte: UInt8) -> Double {
            let value = Double(byte) / 255
            if value <= 0.04045 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// Studio rule: luminance above 0.55 is a light place colour.
    public var isLight: Bool {
        relativeLuminance > 0.55
    }

    func contrast(against other: RGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static let white = RGB(hex: 0xFFFFFF)
    static let ink = RGB(hex: 0x111111)

    static func lerp(_ from: RGB, _ to: RGB, _ t: Double) -> RGB {
        let clamped = min(1, max(0, t))
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            let value = Double(a) + (Double(b) - Double(a)) * clamped
            return UInt8(min(255, max(0, value.rounded())))
        }
        return RGB(r: mix(from.r, to.r), g: mix(from.g, to.g), b: mix(from.b, to.b))
    }

    static func bestText(on background: RGB) -> RGB {
        let whiteContrast = white.contrast(against: background)
        let inkContrast = ink.contrast(against: background)
        return whiteContrast >= inkContrast ? white : ink
    }
}
