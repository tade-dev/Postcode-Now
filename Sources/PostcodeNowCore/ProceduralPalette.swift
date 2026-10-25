import Foundation

/// A permanent, contrast-safe colour for any UK outcode.
///
/// The hue comes from a stable hash so a postcode always looks the same, and
/// neighbouring outcodes look different. Lightness and chroma are forced into
/// one of two OKLCH bands, so the 4.5:1 contrast floors hold by construction
/// rather than by luck, and every place colour is the same brightness to the
/// eye regardless of hue.
public enum ProceduralPalette {
    /// Dark yellows have nowhere to go: sRGB has no saturated dark yellow, so
    /// gamut mapping strips the chroma out of the deep band from 65 to 130 and
    /// leaves olive drab. The wheel skips that arc and compresses the rest
    /// into what is left. The bounds are where the swatches stop reading as
    /// brown and start reading as green again.
    private static let muddyStart: Double = 65
    private static let muddyEnd: Double = 130

    private static let deepLightness: Double = 0.35
    private static let deepChroma: Double = 0.11
    private static let paleLightness: Double = 0.92
    private static let paleChroma: Double = 0.045

    private static let deepAccentLightness: Double = 0.72
    private static let deepAccentChroma: Double = 0.15
    private static let paleAccentLightness: Double = 0.45
    private static let paleAccentChroma: Double = 0.14

    /// A fixed rotation would make the accent hue a function of the primary
    /// hue alone, which parked a magenta accent on every green place colour.
    private static let accentRotations: [Double] = [150, 185, 220]

    public static func theme(forOutcode outcode: String) -> PlaceTheme {
        resolve(outcode).theme
    }

    /// Exposed for test: the hue this outcode resolves to, in degrees.
    public static func hue(forOutcode outcode: String) -> Double {
        let digest = hash(normalize(outcode))
        let span = 360 - (muddyEnd - muddyStart)
        let raw = Double(digest % 100_000) / 100_000 * span
        return raw < muddyStart ? raw : raw + (muddyEnd - muddyStart)
    }

    /// Exposed for test: the accent rotation this outcode ends up on, in
    /// degrees from the primary hue, after any stepping by the search loop.
    public static func accentRotation(forOutcode outcode: String) -> Int {
        Int(resolve(outcode).rotation)
    }

    private static func resolve(_ outcode: String) -> (theme: PlaceTheme, rotation: Double) {
        let key = normalize(outcode)
        let digest = hash(key)
        let baseHue = hue(forOutcode: outcode)
        let isPale = digest % 6 == 0

        let primary = isPale
            ? RGB.inGamut(okL: paleLightness, chroma: paleChroma, hue: baseHue)
            : RGB.inGamut(okL: deepLightness, chroma: deepChroma, hue: baseHue)

        let accent = accentColour(baseHue: baseHue, digest: digest, isPale: isPale, on: primary)

        let theme = PlaceTheme(
            id: key,
            primary: primary,
            onPrimary: RGB.bestText(on: primary),
            accent: accent.colour,
            onAccent: RGB.bestText(on: accent.colour)
        )
        return (theme, accent.rotation)
    }

    /// Starts from the rotation this outcode's hash picked, then steps around
    /// the wheel until the accent clears 3:1 against the place colour and can
    /// carry readable text. The first candidate almost always wins; the loop
    /// is the guarantee, not the common path.
    private static func accentColour(
        baseHue: Double,
        digest: UInt64,
        isPale: Bool,
        on primary: RGB
    ) -> (rotation: Double, colour: RGB) {
        let lightness = isPale ? paleAccentLightness : deepAccentLightness
        let chroma = isPale ? paleAccentChroma : deepAccentChroma
        // A different slice of the digest than the pale selector, so which
        // rotation an outcode gets is independent of which band it is in.
        let start = accentRotations[Int((digest >> 8) % UInt64(accentRotations.count))]

        for step in 0..<12 {
            let rotation = start + Double(step) * 12
            let candidate = RGB.inGamut(
                okL: lightness,
                chroma: chroma,
                hue: baseHue + rotation
            )
            let readable = RGB.bestText(on: candidate)
            if candidate.contrast(against: primary) >= 3.0,
               readable.contrast(against: candidate) >= ThemeInterpolation.controlContrastFloor {
                return (rotation, candidate)
            }
        }
        return (0, RGB.bestText(on: primary))
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
