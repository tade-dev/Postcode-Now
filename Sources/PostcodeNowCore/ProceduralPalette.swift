import Foundation

/// A permanent, contrast-safe colour for any UK outcode.
///
/// The hue comes from a stable hash so a postcode always looks the same, and
/// neighbouring outcodes look different. Lightness is forced into one of two
/// bands so the 4.5:1 contrast floors hold by construction rather than by luck.
public enum ProceduralPalette {
    /// Hues in 52..<78 read as muddy olive at these lightness bands, so the
    /// wheel skips that arc and compresses the rest into what is left.
    private static let muddyStart: Double = 52
    private static let muddyEnd: Double = 78

    private static let deepLightness: Double = 0.22
    private static let paleLightness: Double = 0.88
    private static let deepSaturation: Double = 0.52
    private static let paleSaturation: Double = 0.34

    public static func theme(forOutcode outcode: String) -> PlaceTheme {
        let key = normalize(outcode)
        let digest = hash(key)
        let baseHue = hue(forOutcode: outcode)
        let isPale = digest % 6 == 0

        let primary = isPale
            ? RGB(hue: baseHue, saturation: paleSaturation, lightness: paleLightness)
            : RGB(hue: baseHue, saturation: deepSaturation, lightness: deepLightness)

        let accent = accentColor(baseHue: baseHue, isPale: isPale, on: primary)

        return PlaceTheme(
            id: key,
            primary: primary,
            onPrimary: RGB.bestText(on: primary),
            accent: accent,
            onAccent: RGB.bestText(on: accent)
        )
    }

    /// Exposed for test: the hue this outcode resolves to, in degrees.
    public static func hue(forOutcode outcode: String) -> Double {
        let digest = hash(normalize(outcode))
        let span = 360 - (muddyEnd - muddyStart)
        let raw = Double(digest % 100_000) / 100_000 * span
        return raw < muddyStart ? raw : raw + (muddyEnd - muddyStart)
    }

    /// Steps around the wheel until the accent clears 3:1 against the place
    /// colour and can carry readable text. The first candidate almost always
    /// wins; the loop is the guarantee, not the common path.
    private static func accentColor(baseHue: Double, isPale: Bool, on primary: RGB) -> RGB {
        let lightness = isPale ? 0.32 : 0.68
        let saturation = isPale ? 0.62 : 0.74
        for step in 0..<12 {
            let candidate = RGB(
                hue: baseHue + 150 + Double(step) * 12,
                saturation: saturation,
                lightness: lightness
            )
            let readable = RGB.bestText(on: candidate)
            if candidate.contrast(against: primary) >= 3.0,
               readable.contrast(against: candidate) >= ThemeInterpolation.controlContrastFloor {
                return candidate
            }
        }
        return RGB.bestText(on: primary)
    }

    private static func normalize(_ outcode: String) -> String {
        outcode.uppercased().filter { !$0.isWhitespace }
    }

    /// FNV-1a. Stable across launches and platforms, unlike Hasher.
    private static func hash(_ value: String) -> UInt64 {
        var digest: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            digest ^= UInt64(byte)
            digest = digest &* 0x0000_0100_0000_01b3
        }
        return digest
    }
}
