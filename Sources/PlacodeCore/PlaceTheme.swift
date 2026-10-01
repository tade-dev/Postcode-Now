import Foundation

public struct PlaceTheme: Equatable, Hashable, Sendable {
    public var id: String
    public var primary: RGB
    public var onPrimary: RGB
    public var accent: RGB
    public var onAccent: RGB

    public static let locateDark = PlaceTheme(
        id: "locate.dark",
        primary: RGB(hex: 0x000000),
        onPrimary: RGB(hex: 0xFFFFFF),
        accent: RGB(hex: 0xFFFFFF),
        onAccent: RGB(hex: 0x111111)
    )

    public static let locateLight = PlaceTheme(
        id: "locate.light",
        primary: RGB(hex: 0xF2F2F7),
        onPrimary: RGB(hex: 0x000000),
        accent: RGB(hex: 0x000000),
        onAccent: RGB(hex: 0xFFFFFF)
    )

    public static let neutral = PlaceTheme(
        id: "neutral",
        primary: RGB(hex: 0x111111),
        onPrimary: RGB(hex: 0xFFFFFF),
        accent: RGB(hex: 0xFFFFFF),
        onAccent: RGB(hex: 0x111111)
    )
}

public enum PlacePalette {
    public static func resolve(outcode: String, district: String?) -> PlaceTheme {
        let key = outcode.uppercased().filter { !$0.isWhitespace }
        if let theme = byOutcode[key] {
            return theme
        }
        if let district {
            let normalized = normalizeDistrict(district)
            if let id = districtAliases[normalized], let theme = byOutcode[id] {
                return theme
            }
        }
        return .neutral
    }

    static var curated: [PlaceTheme] {
        curatedOrder.compactMap { byOutcode[$0] }
    }

    static func normalizeDistrict(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefix = "city of "
        if text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        return text
    }

    private static let curatedOrder = [
        "M1", "E1", "G1", "CF10", "BS1", "L1", "EH1", "LS1", "B1", "NE1", "EX1",
    ]

    private static let byOutcode: [String: PlaceTheme] = [
        "M1": make("M1", 0xC41E3A, 0xFFFFFF, 0xF5D76E, 0x111111),
        "E1": make("E1", 0x1A1A2E, 0xFFFFFF, 0xE94560, 0x111111),
        "G1": make("G1", 0x0B3D2E, 0xFFFFFF, 0xF4A261, 0x111111),
        "CF10": make("CF10", 0x0D5C75, 0xFFFFFF, 0xFFB703, 0x111111),
        "BS1": make("BS1", 0x5B2C6F, 0xFFFFFF, 0x2ECC71, 0x111111),
        "L1": make("L1", 0x1B4F72, 0xFFFFFF, 0xE74C3C, 0x111111),
        "EH1": make("EH1", 0x2C3E50, 0xFFFFFF, 0xAED6F1, 0x111111),
        "LS1": make("LS1", 0x1C2833, 0xFFFFFF, 0xF39C12, 0x111111),
        "B1": make("B1", 0x6C3483, 0xFFFFFF, 0x58D68D, 0x111111),
        "NE1": make("NE1", 0x1A5276, 0xFFFFFF, 0xE67E22, 0x111111),
        "EX1": make("EX1", 0xE8DCC4, 0x1C1812, 0x1C1812, 0xFFFCF5),
    ]

    private static let districtAliases: [String: String] = [
        "manchester": "M1",
        "glasgow": "G1",
        "cardiff": "CF10",
        "bristol": "BS1",
        "liverpool": "L1",
        "edinburgh": "EH1",
        "leeds": "LS1",
        "birmingham": "B1",
        "newcastle upon tyne": "NE1",
        "newcastle": "NE1",
    ]

    private static func make(
        _ id: String,
        _ primary: UInt32,
        _ onPrimary: UInt32,
        _ accent: UInt32,
        _ onAccent: UInt32
    ) -> PlaceTheme {
        PlaceTheme(
            id: id,
            primary: RGB(hex: primary),
            onPrimary: RGB(hex: onPrimary),
            accent: RGB(hex: accent),
            onAccent: RGB(hex: onAccent)
        )
    }
}

public enum ThemeInterpolation {
    static let postcodeContrastFloor = 4.5
    static let controlContrastFloor = 4.5

    public static func frame(from: PlaceTheme, to: PlaceTheme, t: Double) -> PlaceTheme {
        if t <= 0 { return from }
        if t >= 1 { return to }
        let primary = RGB.lerp(from.primary, to.primary, t)
        let accent = RGB.lerp(from.accent, to.accent, t)
        return PlaceTheme(
            id: to.id,
            primary: primary,
            onPrimary: traveling(
                from.onPrimary,
                to.onPrimary,
                on: primary,
                t: t,
                minimum: postcodeContrastFloor
            ),
            accent: accent,
            onAccent: traveling(
                from.onAccent,
                to.onAccent,
                on: accent,
                t: t,
                minimum: controlContrastFloor
            )
        )
    }

    private static func traveling(
        _ from: RGB,
        _ to: RGB,
        on background: RGB,
        t: Double,
        minimum: Double
    ) -> RGB {
        let mixed = RGB.lerp(from, to, t)
        if mixed.contrast(against: background) >= minimum {
            return mixed
        }
        if to.contrast(against: background) >= minimum {
            return to
        }
        if from.contrast(against: background) >= minimum {
            return from
        }
        return RGB.bestText(on: background)
    }
}
