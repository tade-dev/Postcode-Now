# PostcodeNow Reveal Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app's 0.65s settle and its hard cut between locating and place with one continuous ~1.5s performance — scanning rings collapse into a lock, stretch into a line, and emit the postcode characters, which emit the place colour.

**Architecture:** Motion stays a pure function in the `PostcodeNowCore` SPM package — `RevealTimeline.sample(...) -> RevealSample` — with SwiftUI views as dumb renderers driven by one `Animatable` Double. The ring and the postcode move into a single `RevealCanvas` that is never torn down, so the transformation can be continuous. Colour becomes procedural so every UK postcode gets a payoff, not just the 11 curated outcodes.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+, XCTest, Swift Package Manager. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-14-reveal-motion-design.md`

## Global Constraints

- Platform floor is iOS 17 / macOS 13, Swift tools 5.9. Do not raise them.
- No new package dependencies. `Package.swift` dependency list stays empty.
- `PostcodeNowCore` must not import UIKit or SwiftUI. It is pure, cross-platform, and that is what makes it testable. UIKit-dependent code belongs in the `PostcodeNow/` app target.
- Contrast floors are 4.5:1 for `onPrimary` against `primary` and for `onAccent` against `accent`. `ThemeInterpolation.postcodeContrastFloor` and `.controlContrastFloor` already hold these values. Never lower them.
- Reduce Motion must return the fully settled state for every input — never a shortened animation.
- The app name in all user-facing copy is `PostcodeNow`. Never `Placode`.
- All 28 existing tests must stay green except the `MotionTests` class, which Task 4 deletes and replaces.
- Portrait only. Do not add orientations.
- Every commit message ends with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## Review Focus

Five conditions the spec implies but does not pin, ordered by how likely they are to bite a real user. Each has a test assigned to the task that owns the code.

1. **A cached GPS fix returns in ~50ms**, so `handoffLoop` is near 0 and the scan rings are still tiny. The collapse must read as a collapse, not as rings appearing from nothing. Pinned in Task 3.
2. **The user retries while a reveal is in flight** (`model.start()` from the outdated banner). The clock must reset to searching cleanly and haptic cues must not double-fire. Pinned in Tasks 8 and 9.
3. **`GIR 0AA`** — the Giro special case `UKPostcode` explicitly supports. Its outcode has no digit, so the hash must still produce a contrast-safe theme, and a 3-letter outcode must lay out. Pinned in Tasks 1 and 6.
4. **The notice banner is present** (outdated or approximate fix), which pushes the hero down the screen. The wash must originate from the hero's *actual* baseline, not an assumed centre. Pinned in Task 7.
5. **The app is backgrounded mid-reveal and returns.** SwiftUI does not advance animations in the background, so `elapsed` can return stale. The reveal must land settled rather than resume from a stale value. Pinned in Task 8.

---

### Task 1: Procedural colour for every postcode

`PlacePalette` curates 11 outcodes; every other UK postcode falls through to grey `#111111`, so the Act 4 payoff never happens for most users. This task gives every outcode a permanent, contrast-safe colour. It ships independently — the existing `SettleTimeline` keeps working and users get colour immediately.

**Files:**
- Modify: `Sources/PostcodeNowCore/RGB.swift` (add an HSL initialiser)
- Create: `Sources/PostcodeNowCore/ProceduralPalette.swift`
- Modify: `Sources/PostcodeNowCore/PlaceTheme.swift:35-47` (`PlacePalette.resolve` falls through to the generator instead of `.neutral`)
- Create: `Tests/PostcodeNowCoreTests/ProceduralPaletteTests.swift`

**Interfaces:**
- Consumes: `RGB.bestText(on:)`, `RGB.contrast(against:)`, `PlaceTheme` — all existing.
- Produces: `RGB.init(hue:saturation:lightness:)` where hue is 0–360 and saturation/lightness are 0–1. `ProceduralPalette.theme(forOutcode: String) -> PlaceTheme`. `PlacePalette.resolve(outcode:district:)` keeps its existing signature and return type.

- [ ] **Step 1: Write the failing test for HSL conversion**

Create `Tests/PostcodeNowCoreTests/ProceduralPaletteTests.swift`:

```swift
import Foundation
import XCTest
@testable import PostcodeNowCore

final class HSLTests: XCTestCase {
    func testKnownConversions() {
        XCTAssertEqual(RGB(hue: 0, saturation: 1, lightness: 0.5), RGB(hex: 0xFF0000))
        XCTAssertEqual(RGB(hue: 120, saturation: 1, lightness: 0.5), RGB(hex: 0x00FF00))
        XCTAssertEqual(RGB(hue: 240, saturation: 1, lightness: 0.5), RGB(hex: 0x0000FF))
        XCTAssertEqual(RGB(hue: 0, saturation: 0, lightness: 1), RGB(hex: 0xFFFFFF))
        XCTAssertEqual(RGB(hue: 0, saturation: 0, lightness: 0), RGB(hex: 0x000000))
        XCTAssertEqual(RGB(hue: 0, saturation: 0, lightness: 0.5), RGB(hex: 0x808080))
    }

    func testHueWrapsAndClamps() {
        XCTAssertEqual(RGB(hue: 360, saturation: 1, lightness: 0.5), RGB(hex: 0xFF0000))
        XCTAssertEqual(RGB(hue: -120, saturation: 1, lightness: 0.5), RGB(hex: 0x0000FF))
        XCTAssertEqual(RGB(hue: 480, saturation: 1, lightness: 0.5), RGB(hex: 0x00FF00))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter HSLTests`
Expected: FAIL — compile error, `RGB` has no initialiser `init(hue:saturation:lightness:)`.

- [ ] **Step 3: Add the HSL initialiser**

Append to `Sources/PostcodeNowCore/RGB.swift`, inside the `RGB` struct, after `init(hex:)`:

```swift
    /// Hue in degrees (wraps), saturation and lightness in 0...1 (clamped).
    public init(hue: Double, saturation: Double, lightness: Double) {
        let h = ((hue.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) / 360
        let s = min(1, max(0, saturation))
        let l = min(1, max(0, lightness))

        func component(_ offset: Double) -> UInt8 {
            let k = (offset + h * 12).truncatingRemainder(dividingBy: 12)
            let a = s * min(l, 1 - l)
            let value = l - a * max(-1, min(min(k - 3, 9 - k), 1))
            return UInt8((value * 255).rounded())
        }

        self.init(r: component(0), g: component(8), b: component(4))
    }
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter HSLTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Write the failing test for the generator**

Append to `Tests/PostcodeNowCoreTests/ProceduralPaletteTests.swift`:

```swift
final class ProceduralPaletteTests: XCTestCase {
    /// Every outcode shape UKPostcode accepts, plus the Giro special case.
    private func everyOutcodeShape() -> [String] {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let digits = Array("0123456789")
        var shapes: [String] = ["GIR"]
        for a in letters {
            for d in digits {
                shapes.append("\(a)\(d)")
                for t in letters { shapes.append("\(a)\(d)\(t)") }
                for t in digits { shapes.append("\(a)\(d)\(t)") }
            }
        }
        for a in letters.prefix(8) {
            for b in letters {
                for d in digits {
                    shapes.append("\(a)\(b)\(d)")
                    shapes.append("\(a)\(b)\(d)A")
                }
            }
        }
        return shapes
    }

    func testIsDeterministic() {
        for outcode in ["M1", "SW1A", "GIR", "ZZ9", "B33"] {
            XCTAssertEqual(
                ProceduralPalette.theme(forOutcode: outcode),
                ProceduralPalette.theme(forOutcode: outcode)
            )
        }
    }

    func testCaseAndSpacingDoNotChangeTheColour() {
        XCTAssertEqual(
            ProceduralPalette.theme(forOutcode: "sw1a"),
            ProceduralPalette.theme(forOutcode: " SW1A ")
        )
    }

    func testNeighbouringOutcodesDiffer() {
        let one = ProceduralPalette.theme(forOutcode: "B33")
        let two = ProceduralPalette.theme(forOutcode: "B34")
        XCTAssertNotEqual(one.primary, two.primary)
    }

    func testEveryOutcodeShapeClearsBothContrastFloors() {
        for outcode in everyOutcodeShape() {
            let theme = ProceduralPalette.theme(forOutcode: outcode)
            XCTAssertGreaterThanOrEqual(
                theme.onPrimary.contrast(against: theme.primary),
                ThemeInterpolation.postcodeContrastFloor,
                "onPrimary failed for \(outcode)"
            )
            XCTAssertGreaterThanOrEqual(
                theme.onAccent.contrast(against: theme.accent),
                ThemeInterpolation.controlContrastFloor,
                "onAccent failed for \(outcode)"
            )
            XCTAssertGreaterThanOrEqual(
                theme.accent.contrast(against: theme.primary),
                3.0,
                "accent is invisible on primary for \(outcode)"
            )
        }
    }

    func testCuratedOutcodesAreReturnedUnchanged() {
        let manchester = PlacePalette.resolve(outcode: "M1", district: nil)
        XCTAssertEqual(manchester.primary, RGB(hex: 0xC41E3A))
        XCTAssertEqual(manchester.accent, RGB(hex: 0xF5D76E))

        let exmouth = PlacePalette.resolve(outcode: "EX1", district: nil)
        XCTAssertEqual(exmouth.primary, RGB(hex: 0xE8DCC4))
    }

    func testUncuratedOutcodeIsNoLongerNeutral() {
        let generated = PlacePalette.resolve(outcode: "B33", district: nil)
        XCTAssertNotEqual(generated.primary, PlaceTheme.neutral.primary)
        XCTAssertEqual(generated.id, "B33")
    }

    func testGiroGetsAUsableTheme() {
        let giro = PlacePalette.resolve(outcode: "GIR", district: nil)
        XCTAssertEqual(giro.id, "GIR")
        XCTAssertGreaterThanOrEqual(
            giro.onPrimary.contrast(against: giro.primary),
            ThemeInterpolation.postcodeContrastFloor
        )
    }

    func testMuddyHuesAreExcluded() {
        for outcode in everyOutcodeShape() {
            let hue = ProceduralPalette.hue(forOutcode: outcode)
            XCTAssertFalse(
                (52.0..<78.0).contains(hue),
                "\(outcode) landed in the muddy olive band at \(hue)"
            )
        }
    }
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `swift test --filter ProceduralPaletteTests`
Expected: FAIL — `ProceduralPalette` is not defined.

- [ ] **Step 7: Write the generator**

Create `Sources/PostcodeNowCore/ProceduralPalette.swift`:

```swift
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
        return RGB.bestText(on: primary) == RGB.white ? RGB.white : RGB.ink
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
```

- [ ] **Step 8: Make `PlacePalette` fall through to the generator**

In `Sources/PostcodeNowCore/PlaceTheme.swift`, replace the body of `PlacePalette.resolve` (currently returns `.neutral` as its last line):

```swift
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
        guard !key.isEmpty else { return .neutral }
        return ProceduralPalette.theme(forOutcode: key)
    }
```

- [ ] **Step 9: Run the whole suite**

Run: `swift test`
Expected: PASS. The pre-existing `testDistrictFallbackAndNeutral` asserts an uncurated outcode returns `.neutral`; it is now wrong by design. Open `Tests/PostcodeNowCoreTests/PostcodeNowCoreTests.swift:82`, read `testDistrictFallbackAndNeutral`, and change only the assertion that expects `.neutral` for a real outcode so it expects a generated theme with that outcode's `id`. Leave the empty-string case asserting `.neutral`. Then re-run `swift test` until green.

- [ ] **Step 10: Review a contact sheet before locking the generator**

Spec Risk 3: contrast-safe does not mean attractive. A hash can land on a muddy olive or a sickly chartreuse and still pass every contrast assertion.

Temporarily append this to `Tests/PostcodeNowCoreTests/ProceduralPaletteTests.swift`:

```swift
final class ContactSheetTests: XCTestCase {
    func testPrintContactSheet() {
        let outcodes = [
            "SW1A", "W1A", "EC1A", "N1", "SE1", "NW1", "OX1", "CB1",
            "BA1", "BN1", "CT1", "DH1", "DT1", "GL1", "HU1", "IP1",
            "KT1", "LE1", "LN1", "ME1", "NG1", "NR1", "PE1", "PL1",
            "RG1", "SA1", "TQ1", "WF1", "YO1", "AB1", "DD1", "FK1",
            "IV1", "KY1", "PA1", "PH1", "TD1", "ZE1", "GIR", "B33",
        ]
        print("| outcode | primary | accent | hue |")
        print("|---|---|---|---|")
        for outcode in outcodes {
            let theme = ProceduralPalette.theme(forOutcode: outcode)
            let hue = Int(ProceduralPalette.hue(forOutcode: outcode).rounded())
            print(
                "| \(outcode) | #\(String(format: "%06X", theme.primary.hex))"
                    + " | #\(String(format: "%06X", theme.accent.hex)) | \(hue) |"
            )
        }
    }
}
```

Run: `swift test --filter ContactSheetTests`

Copy the printed markdown table into the task's report. Render the hex values somewhere you can actually see them — paste the table into any colour previewer, or build a one-off HTML swatch page — because this cannot be judged from hex codes alone.

If any colour is visibly muddy or garish, widen the excluded band via `ProceduralPalette.muddyStart` / `muddyEnd`, update `testMuddyHuesAreExcluded` to the new range, and re-run. Do not proceed with a sheet you would not ship.

Delete `ContactSheetTests` before committing — it is a looking tool, not a test, and it has no assertions.

- [ ] **Step 11: Commit**

```bash
git add Sources/PostcodeNowCore/RGB.swift \
        Sources/PostcodeNowCore/ProceduralPalette.swift \
        Sources/PostcodeNowCore/PlaceTheme.swift \
        Tests/PostcodeNowCoreTests/ProceduralPaletteTests.swift \
        Tests/PostcodeNowCoreTests/PostcodeNowCoreTests.swift
git commit -m "$(cat <<'EOF'
Give every UK postcode its own place colour

The palette curated 11 outcodes and everything else washed to grey
#111111, so the place-colour payoff never happened for most users.

Hue now comes from an FNV-1a hash of the outcode, forced into one of two
lightness bands so both 4.5:1 contrast floors hold by construction. The
11 curated themes stay as exact overrides.

Verified across every outcode shape UKPostcode accepts, including GIR.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Four-act timing constants and sample types

Pure data and scaffolding. Nothing animates yet; this task exists so the next two have exact names and numbers to build against. `SettleTimeline` and the old `MotionTiming` stay in place and working until Task 4 removes them.

**Files:**
- Create: `Sources/PostcodeNowCore/RevealSample.swift`
- Create: `Sources/PostcodeNowCore/RevealTiming.swift`
- Modify: `Sources/PostcodeNowCore/Easing.swift` (add two curves)
- Create: `Tests/PostcodeNowCoreTests/RevealTimingTests.swift`

**Interfaces:**
- Consumes: `SpringCurve.settleTime(response:dampingFraction:tolerance:)` and `SpringCurve.peak(response:dampingFraction:until:)`, both existing.
- Produces: `RingState`, `CharacterState`, `RevealSample`, `RevealSample.settled(outcodeCount:incodeCount:)`, the `RevealTiming` enum with all four acts' constants, `RevealTiming.characterStart(index:outcodeCount:)`, `RevealTiming.charactersSettled(outcodeCount:incodeCount:)`, `RevealTiming.ctaStart(outcodeCount:incodeCount:)`, `Easing.easeOutBack(_:)`, `Easing.easeInCubic(_:)`.

A separate `RevealTiming` enum is used rather than extending `MotionTiming`, so the old and new systems can coexist until Task 4 deletes the old one.

- [ ] **Step 1: Write the failing test for the timing arithmetic**

Create `Tests/PostcodeNowCoreTests/RevealTimingTests.swift`:

```swift
import Foundation
import XCTest
@testable import PostcodeNowCore

final class RevealTimingTests: XCTestCase {
    func testActBoundariesAreOrdered() {
        XCTAssertEqual(RevealTiming.collapse, 0.28)
        XCTAssertEqual(RevealTiming.lockHaptic, 0.26)
        XCTAssertEqual(RevealTiming.stretchStart, 0.45)
        XCTAssertEqual(RevealTiming.bloomStart, 0.62)
        XCTAssertEqual(RevealTiming.washStart, 0.70)

        XCTAssertLessThan(RevealTiming.lockHaptic, RevealTiming.collapse)
        XCTAssertLessThan(RevealTiming.collapse, RevealTiming.stretchStart)
        XCTAssertEqual(
            RevealTiming.stretchStart + RevealTiming.stretch,
            RevealTiming.bloomStart,
            accuracy: 0.0001
        )
        XCTAssertLessThan(RevealTiming.bloomStart, RevealTiming.washStart)
    }

    func testCharacterStartsStaggerAndTakeABeatAfterTheOutcode() {
        // "M1 1AE" -> outcode 2, incode 3.
        let first = RevealTiming.characterStart(index: 0, outcodeCount: 2)
        let second = RevealTiming.characterStart(index: 1, outcodeCount: 2)
        let third = RevealTiming.characterStart(index: 2, outcodeCount: 2)

        XCTAssertEqual(first, RevealTiming.bloomStart, accuracy: 0.0001)
        XCTAssertEqual(second - first, RevealTiming.characterStagger, accuracy: 0.0001)
        // The first incode character waits an extra beat.
        XCTAssertEqual(
            third - second,
            RevealTiming.characterStagger + RevealTiming.beat,
            accuracy: 0.0001
        )
    }

    func testCTAWaitsForTheLastCharacter() {
        let shortCode = RevealTiming.ctaStart(outcodeCount: 2, incodeCount: 3)
        let longCode = RevealTiming.ctaStart(outcodeCount: 4, incodeCount: 3)
        XCTAssertLessThan(shortCode, longCode)
        XCTAssertGreaterThanOrEqual(shortCode, RevealTiming.ctaFloor)
    }

    func testDurationStaysInsideTheBudgetForEveryPostcodeShape() {
        // Valid UK hero strings run 5 to 7 characters: A9 9AA up to AA9A 9AA.
        for outcodeCount in 2...4 {
            let total = RevealTiming.duration(outcodeCount: outcodeCount, incodeCount: 3)
            XCTAssertGreaterThanOrEqual(total, 1.4, "too fast at outcode \(outcodeCount)")
            XCTAssertLessThanOrEqual(total, 1.8, "too slow at outcode \(outcodeCount)")
        }
    }

    func testSpringsDoNotOvershootTheHouseLimit() {
        XCTAssertLessThanOrEqual(
            SpringCurve.peak(
                response: RevealTiming.characterResponse,
                dampingFraction: RevealTiming.characterDamping
            ),
            1.06
        )
        XCTAssertLessThanOrEqual(
            SpringCurve.peak(
                response: RevealTiming.ctaResponse,
                dampingFraction: RevealTiming.ctaDamping
            ),
            1.015
        )
    }

    func testEasingCurvesAreAnchored() {
        XCTAssertEqual(Easing.easeInCubic(0), 0, accuracy: 0.0001)
        XCTAssertEqual(Easing.easeInCubic(1), 1, accuracy: 0.0001)
        XCTAssertEqual(Easing.easeOutBack(0), 0, accuracy: 0.0001)
        XCTAssertEqual(Easing.easeOutBack(1), 1, accuracy: 0.0001)
        // easeOutBack overshoots on the way, which is the point of it.
        XCTAssertGreaterThan(Easing.easeOutBack(0.7), 1.0)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter RevealTimingTests`
Expected: FAIL — `RevealTiming` is not defined.

- [ ] **Step 3: Add the two easing curves**

Append inside `enum Easing` in `Sources/PostcodeNowCore/Easing.swift`:

```swift
    static func easeInCubic(_ t: Double) -> Double {
        let x = clamp01(t)
        return x * x * x
    }

    /// Overshoots past 1 before settling. Used for the lock's anticipation.
    static func easeOutBack(_ t: Double) -> Double {
        let x = clamp01(t)
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
```

- [ ] **Step 4: Write the timing constants**

Create `Sources/PostcodeNowCore/RevealTiming.swift`:

```swift
import Foundation

/// Durations for the four-act reveal, measured in seconds from the instant
/// the location fix lands. See docs/superpowers/specs/2026-10-14-reveal-motion-design.md.
public enum RevealTiming {
    // MARK: Act 1 — searching (loops until the fix arrives)

    public static let scanLoop: Double = 1.6
    /// Phase offset between the three scan rings, as a fraction of the loop.
    public static let scanStagger: Double = 0.33
    public static let scanInnerRadius: Double = 36
    public static let scanOuterRadius: Double = 104
    public static let scanPeakOpacity: Double = 0.26
    public static let scanRingCount: Int = 3

    // MARK: Act 2 — the lock

    public static let collapse: Double = 0.28
    public static let lockHaptic: Double = 0.26
    public static let lockRadius: Double = 28
    public static let lockContracted: Double = 24
    public static let captionOut: Double = 0.18

    // MARK: Act 3 — the bloom

    public static let stretchStart: Double = 0.45
    public static let stretch: Double = 0.17
    public static let bloomStart: Double = 0.62
    public static let characterStagger: Double = 0.045
    public static let beat: Double = 0.05
    public static let characterResponse: Double = 0.30
    public static let characterDamping: Double = 0.80
    /// How long after a character starts moving before it reads as landed.
    public static let characterLand: Double = 0.15
    public static let lineDissolveStart: Double = 0.95
    public static let lineDissolve: Double = 0.25

    // MARK: Act 4 — the wash

    public static let washStart: Double = 0.70
    public static let wash: Double = 0.50
    public static let labelStart: Double = 1.05
    public static let label: Double = 0.25
    public static let bannerStart: Double = 0.70
    public static let banner: Double = 0.20

    // MARK: The CTA, which always follows the last character

    public static let ctaResponse: Double = 0.32
    public static let ctaDamping: Double = 0.88
    /// The CTA starts slightly before the code finishes settling, so the
    /// screen never reads as empty between the two.
    public static let ctaOverlap: Double = 0.15
    public static let ctaFloor: Double = 1.0

    // MARK: Derived

    /// When character `index` begins its spring. The incode waits one beat
    /// after the outcode, which is what makes the code read in two halves.
    public static func characterStart(index: Int, outcodeCount: Int) -> Double {
        let staggered = bloomStart + characterStagger * Double(index)
        return index < outcodeCount ? staggered : staggered + beat
    }

    public static func charactersSettled(outcodeCount: Int, incodeCount: Int) -> Double {
        let last = max(0, outcodeCount + incodeCount - 1)
        let start = characterStart(index: last, outcodeCount: outcodeCount)
        return start + SpringCurve.settleTime(
            response: characterResponse,
            dampingFraction: characterDamping
        )
    }

    public static func ctaStart(outcodeCount: Int, incodeCount: Int) -> Double {
        let settled = charactersSettled(outcodeCount: outcodeCount, incodeCount: incodeCount)
        return max(ctaFloor, settled - ctaOverlap)
    }

    public static func duration(outcodeCount: Int, incodeCount: Int) -> Double {
        ctaStart(outcodeCount: outcodeCount, incodeCount: incodeCount)
            + SpringCurve.settleTime(response: ctaResponse, dampingFraction: ctaDamping)
    }
}
```

- [ ] **Step 5: Run it to verify it passes**

Run: `swift test --filter RevealTimingTests`
Expected: PASS, 6 tests. If `testDurationStaysInsideTheBudgetForEveryPostcodeShape` fails low, raise `ctaFloor`; if it fails high, lower `characterStagger`. Do not change the 1.4–1.8 bounds — they are the spec's contract.

- [ ] **Step 6: Write the failing test for the sample types**

Append to `Tests/PostcodeNowCoreTests/RevealTimingTests.swift`:

```swift
final class RevealSampleTests: XCTestCase {
    func testSettledIsFullyResolved() {
        let settled = RevealSample.settled(outcodeCount: 2, incodeCount: 3)

        XCTAssertEqual(settled.characters.count, 5)
        for character in settled.characters {
            XCTAssertEqual(character.opacity, 1, accuracy: 0.0001)
            XCTAssertEqual(character.scale, 1, accuracy: 0.0001)
            XCTAssertEqual(character.offsetY, 0, accuracy: 0.0001)
        }
        XCTAssertEqual(settled.washProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.ctaOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.sectionOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.districtOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.bannerOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.captionOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(settled.lineOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(settled.lockOpacity, 0, accuracy: 0.0001)
        XCTAssertTrue(settled.rings.allSatisfy { $0.opacity == 0 })
    }

    func testSettledOutcodeCharactersAreBold() {
        let settled = RevealSample.settled(outcodeCount: 2, incodeCount: 3)
        XCTAssertEqual(settled.characters[0].weightBlend, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.characters[1].weightBlend, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.characters[4].weightBlend, 1, accuracy: 0.0001)
    }
}
```

- [ ] **Step 7: Write the sample types**

Create `Sources/PostcodeNowCore/RevealSample.swift`:

```swift
import Foundation

public struct RingState: Equatable, Sendable {
    public var radius: Double
    public var opacity: Double
    public var lineWidth: Double

    public init(radius: Double, opacity: Double, lineWidth: Double) {
        self.radius = radius
        self.opacity = opacity
        self.lineWidth = lineWidth
    }
}

public struct CharacterState: Equatable, Sendable {
    public var opacity: Double
    public var offsetY: Double
    public var scale: Double
    /// 0 renders the medium weight, 1 the bold. Crossfaded between.
    public var weightBlend: Double

    public init(opacity: Double, offsetY: Double, scale: Double, weightBlend: Double) {
        self.opacity = opacity
        self.offsetY = offsetY
        self.scale = scale
        self.weightBlend = weightBlend
    }
}

/// Everything the canvas needs to draw one frame. Pure data: no UIKit,
/// no SwiftUI, no geometry the view owns.
public struct RevealSample: Equatable, Sendable {
    public var rings: [RingState]
    public var lockRadius: Double
    public var lockOpacity: Double
    /// Fraction of the hero's width the line currently spans, 0...1.
    public var lineLength: Double
    public var lineThickness: Double
    public var lineOpacity: Double
    public var characters: [CharacterState]
    public var washProgress: Double
    public var captionOpacity: Double
    public var wordmarkOpacity: Double
    public var sectionOpacity: Double
    public var districtOpacity: Double
    public var districtOffset: Double
    public var ctaOpacity: Double
    public var ctaOffset: Double
    public var bannerOpacity: Double

    public static func settled(outcodeCount: Int, incodeCount: Int) -> RevealSample {
        RevealSample(
            rings: Array(
                repeating: RingState(radius: RevealTiming.lockRadius, opacity: 0, lineWidth: 1),
                count: RevealTiming.scanRingCount
            ),
            lockRadius: RevealTiming.lockRadius,
            lockOpacity: 0,
            lineLength: 1,
            lineThickness: 0,
            lineOpacity: 0,
            characters: Array(
                repeating: CharacterState(opacity: 1, offsetY: 0, scale: 1, weightBlend: 1),
                count: max(0, outcodeCount + incodeCount)
            ),
            washProgress: 1,
            captionOpacity: 0,
            wordmarkOpacity: 1,
            sectionOpacity: 1,
            districtOpacity: 1,
            districtOffset: 0,
            ctaOpacity: 1,
            ctaOffset: 0,
            bannerOpacity: 1
        )
    }
}
```

- [ ] **Step 8: Run the whole suite**

Run: `swift test`
Expected: PASS. All pre-existing tests plus the new `RevealTimingTests` and `RevealSampleTests`.

- [ ] **Step 9: Commit**

```bash
git add Sources/PostcodeNowCore/RevealTiming.swift \
        Sources/PostcodeNowCore/RevealSample.swift \
        Sources/PostcodeNowCore/Easing.swift \
        Tests/PostcodeNowCoreTests/RevealTimingTests.swift
git commit -m "$(cat <<'EOF'
Add four-act reveal timings and sample types

Pure data and curves for the reveal. Nothing animates yet; this gives
the timeline exact names and numbers to build against.

RevealTiming sits alongside MotionTiming rather than replacing it, so
the existing settle keeps working until the new timeline lands.

The CTA start is derived from when the last character settles rather
than being a constant, so longer postcodes push it later instead of
having the buttons arrive before the code does.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Act 1 scanning and the invisible handoff

The seam this whole redesign exists to remove. Act 1 loops indefinitely; Act 2 must begin from wherever the rings actually were. This task builds the scan and proves the handoff is continuous.

**Files:**
- Create: `Sources/PostcodeNowCore/RevealTimeline.swift`
- Create: `Tests/PostcodeNowCoreTests/RevealTimelineTests.swift`

**Interfaces:**
- Consumes: `RevealTiming.*`, `RingState`, `RevealSample`, `Easing.*` from Task 2.
- Produces: `RevealTimeline.scanRings(loop: Double) -> [RingState]` and `RevealTimeline.sample(elapsed:searchLoop:handoffLoop:outcodeCount:incodeCount:reduceMotion:) -> RevealSample`. In this task `sample` handles only the searching branch (`elapsed == nil`) and the ring layer of the revealing branch; Task 4 fills in the rest.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PostcodeNowCoreTests/RevealTimelineTests.swift`:

```swift
import Foundation
import XCTest
@testable import PostcodeNowCore

final class ScanTests: XCTestCase {
    func testScanProducesThreeStaggeredRings() {
        let rings = RevealTimeline.scanRings(loop: 0)
        XCTAssertEqual(rings.count, RevealTiming.scanRingCount)
        // Staggered, so no two rings share a radius at any single moment.
        XCTAssertNotEqual(rings[0].radius, rings[1].radius)
        XCTAssertNotEqual(rings[1].radius, rings[2].radius)
    }

    func testRingsTravelOutwardAndStayInsideTheirBounds() {
        for step in 0...200 {
            let loop = Double(step) / 200
            for ring in RevealTimeline.scanRings(loop: loop) {
                XCTAssertGreaterThanOrEqual(ring.radius, RevealTiming.scanInnerRadius - 0.001)
                XCTAssertLessThanOrEqual(ring.radius, RevealTiming.scanOuterRadius + 0.001)
                XCTAssertGreaterThanOrEqual(ring.opacity, 0)
                XCTAssertLessThanOrEqual(ring.opacity, RevealTiming.scanPeakOpacity + 0.001)
            }
        }
    }

    func testScanIsSeamlessAcrossTheLoopBoundary() {
        let before = RevealTimeline.scanRings(loop: 0.999)
        let after = RevealTimeline.scanRings(loop: 0.0)
        for index in before.indices {
            // A ring at the end of its travel has faded out, so wrapping it
            // back to the centre must not be visible.
            XCTAssertLessThan(before[index].opacity, 0.02)
            XCTAssertLessThan(after[index].opacity, 0.02)
        }
    }

    func testRingsFadeInFromTheCentreAndOutAtTheEdge() {
        let rings = RevealTimeline.scanRings(loop: 0.0)
        XCTAssertLessThan(rings[0].opacity, 0.02, "a ring at the centre has not faded in yet")

        let midway = RevealTimeline.scanRings(loop: 0.4)
        XCTAssertGreaterThan(midway[0].opacity, 0.05, "a ring mid-travel should be visible")
    }
}

final class HandoffTests: XCTestCase {
    /// The test this redesign exists for. If the rings jump at elapsed = 0,
    /// the user sees a cut and the whole premise fails.
    func testRingsAtElapsedZeroMatchTheScanTheyHandedOffFrom() {
        for step in 0...100 {
            let handoff = Double(step) / 100
            let scanning = RevealTimeline.scanRings(loop: handoff)
            let revealing = RevealTimeline.sample(
                elapsed: 0,
                searchLoop: handoff,
                handoffLoop: handoff,
                outcodeCount: 2,
                incodeCount: 3,
                reduceMotion: false
            )

            for index in scanning.indices {
                XCTAssertEqual(
                    revealing.rings[index].radius,
                    scanning[index].radius,
                    accuracy: 0.0001,
                    "radius jumped at handoffLoop \(handoff), ring \(index)"
                )
                XCTAssertEqual(
                    revealing.rings[index].opacity,
                    scanning[index].opacity,
                    accuracy: 0.0001,
                    "opacity jumped at handoffLoop \(handoff), ring \(index)"
                )
            }
        }
    }

    /// Review Focus 1: a cached fix returns in ~50ms, so the rings are still
    /// near the centre when the collapse starts. It must still read as a
    /// collapse inward, not as rings appearing from nowhere.
    func testACollapseFromAnAlmostUnstartedScanStillTravelsInward() {
        let handoff = 0.01
        let atStart = RevealTimeline.sample(
            elapsed: 0,
            searchLoop: handoff,
            handoffLoop: handoff,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )
        let atEnd = RevealTimeline.sample(
            elapsed: RevealTiming.collapse,
            searchLoop: handoff,
            handoffLoop: handoff,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )

        for index in atStart.rings.indices {
            XCTAssertEqual(
                atEnd.rings[index].radius,
                RevealTiming.lockRadius,
                accuracy: 0.001,
                "ring \(index) did not arrive at the lock radius"
            )
        }
        // The lock ring must carry the moment when the scan rings had no
        // opacity to donate.
        XCTAssertGreaterThan(atEnd.lockOpacity, 0.5)
        XCTAssertLessThan(atStart.lockOpacity, atEnd.lockOpacity)
    }

    func testSearchingBranchIgnoresHandoffEntirely() {
        let a = RevealTimeline.sample(
            elapsed: nil,
            searchLoop: 0.3,
            handoffLoop: 0.0,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )
        let b = RevealTimeline.sample(
            elapsed: nil,
            searchLoop: 0.3,
            handoffLoop: 0.9,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.captionOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(a.washProgress, 0, accuracy: 0.0001)
        XCTAssertTrue(a.characters.allSatisfy { $0.opacity == 0 })
    }

    func testReduceMotionIsAlwaysSettledEvenWhileSearching() {
        let settled = RevealSample.settled(outcodeCount: 2, incodeCount: 3)
        for elapsed in [nil, 0, 0.3, 0.9, 99.0] as [Double?] {
            XCTAssertEqual(
                RevealTimeline.sample(
                    elapsed: elapsed,
                    searchLoop: 0.5,
                    handoffLoop: 0.5,
                    outcodeCount: 2,
                    incodeCount: 3,
                    reduceMotion: true
                ),
                settled
            )
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter ScanTests`
Expected: FAIL — `RevealTimeline` is not defined.

- [ ] **Step 3: Write the scan and the handoff**

Create `Sources/PostcodeNowCore/RevealTimeline.swift`:

```swift
import Foundation

/// The whole reveal as a pure function of time. Views render what this
/// returns and decide nothing themselves.
///
/// Two clocks, deliberately. Act 1 loops for as long as the fix takes, so
/// folding it into one monotonic scalar would let that scalar grow without
/// bound. `searchLoop` is a 0...1 phase; `elapsed` is nil until the fix lands
/// and then counts seconds from it. `handoffLoop` is `searchLoop` frozen at
/// that instant, which is what lets Act 2 start from where the rings actually
/// were instead of snapping to a canonical position.
public enum RevealTimeline {
    public static func duration(outcodeCount: Int, incodeCount: Int) -> Double {
        RevealTiming.duration(outcodeCount: outcodeCount, incodeCount: incodeCount)
    }

    /// Ring positions during Act 1, for a loop phase in 0...1.
    public static func scanRings(loop: Double) -> [RingState] {
        (0..<RevealTiming.scanRingCount).map { index in
            let offset = RevealTiming.scanStagger * Double(index)
            let phase = ((loop + offset).truncatingRemainder(dividingBy: 1) + 1)
                .truncatingRemainder(dividingBy: 1)
            return RingState(
                radius: RevealTiming.scanInnerRadius
                    + (RevealTiming.scanOuterRadius - RevealTiming.scanInnerRadius) * phase,
                opacity: scanOpacity(phase: phase),
                lineWidth: 1
            )
        }
    }

    /// Fades in off the centre and out at the edge, so the wrap from phase 1
    /// back to phase 0 happens while the ring is invisible.
    private static func scanOpacity(phase: Double) -> Double {
        let fadeIn = Easing.clamp01(phase / 0.18)
        let fadeOut = Easing.clamp01((1 - phase) / 0.34)
        return RevealTiming.scanPeakOpacity * fadeIn * fadeOut
    }

    public static func sample(
        elapsed: Double?,
        searchLoop: Double,
        handoffLoop: Double,
        outcodeCount: Int,
        incodeCount: Int,
        reduceMotion: Bool
    ) -> RevealSample {
        if reduceMotion {
            return .settled(outcodeCount: outcodeCount, incodeCount: incodeCount)
        }
        guard let elapsed else {
            return searching(searchLoop: searchLoop, characterCount: outcodeCount + incodeCount)
        }
        return revealing(
            elapsed: max(0, elapsed),
            handoffLoop: handoffLoop,
            outcodeCount: outcodeCount,
            incodeCount: incodeCount
        )
    }

    private static func searching(searchLoop: Double, characterCount: Int) -> RevealSample {
        RevealSample(
            rings: scanRings(loop: searchLoop),
            lockRadius: RevealTiming.lockRadius,
            lockOpacity: 0,
            lineLength: 0,
            lineThickness: 0,
            lineOpacity: 0,
            characters: Array(
                repeating: CharacterState(opacity: 0, offsetY: 0, scale: 0.9, weightBlend: 0),
                count: max(0, characterCount)
            ),
            washProgress: 0,
            captionOpacity: 1,
            wordmarkOpacity: 1,
            sectionOpacity: 0,
            districtOpacity: 0,
            districtOffset: 0,
            ctaOpacity: 0,
            ctaOffset: 0,
            bannerOpacity: 0
        )
    }

    /// Act 2 only in this task. Task 4 adds the bloom, the wash and the chrome.
    private static func revealing(
        elapsed: Double,
        handoffLoop: Double,
        outcodeCount: Int,
        incodeCount: Int
    ) -> RevealSample {
        let collapse = Easing.easeInOutCubic(
            Easing.unit(elapsed, start: 0, duration: RevealTiming.collapse)
        )
        let frozen = scanRings(loop: handoffLoop)
        let rings = frozen.map { ring in
            RingState(
                radius: ring.radius + (RevealTiming.lockRadius - ring.radius) * collapse,
                opacity: ring.opacity * (1 - collapse),
                lineWidth: ring.lineWidth
            )
        }

        var sample = searching(
            searchLoop: handoffLoop,
            characterCount: outcodeCount + incodeCount
        )
        sample.rings = rings
        sample.lockOpacity = collapse
        sample.lockRadius = RevealTiming.lockRadius
            + (RevealTiming.lockContracted - RevealTiming.lockRadius)
            * Easing.easeOutBack(
                Easing.unit(elapsed, start: RevealTiming.collapse, duration: 0.17)
            )
        sample.captionOpacity = 1 - Easing.easeOutCubic(
            Easing.unit(elapsed, start: 0, duration: RevealTiming.captionOut)
        )
        return sample
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ScanTests && swift test --filter HandoffTests`
Expected: PASS, 8 tests. `testRingsAtElapsedZeroMatchTheScanTheyHandedOffFrom` is the one that matters most — it runs 101 handoff positions × 3 rings × 2 properties.

- [ ] **Step 5: Commit**

```bash
git add Sources/PostcodeNowCore/RevealTimeline.swift \
        Tests/PostcodeNowCoreTests/RevealTimelineTests.swift
git commit -m "$(cat <<'EOF'
Add scanning rings and a continuous handoff into the lock

Act 1 loops for as long as the fix takes, so it gets its own 0...1 phase
clock rather than sharing the reveal's monotonic one.

The collapse interpolates from the ring positions frozen at the instant
of handoff, so Act 2 starts exactly where Act 1 left off. Asserted at
101 handoff positions, which is the test this redesign exists for.

Also covers a cached fix arriving in ~50ms, where the rings have barely
left the centre and the lock ring has to carry the moment.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: The bloom, the wash, and the chrome

Fills in Acts 3 and 4, retires `SettleTimeline`, and ports the old motion tests.

**Files:**
- Modify: `Sources/PostcodeNowCore/RevealTimeline.swift` (complete `revealing`)
- Modify: `Tests/PostcodeNowCoreTests/RevealTimelineTests.swift` (append)
- Delete: `Sources/PostcodeNowCore/SettleTimeline.swift`
- Modify: `Sources/PostcodeNowCore/MotionTiming.swift` (strip the constants only `SettleTimeline` used)
- Modify: `Tests/PostcodeNowCoreTests/PostcodeNowCoreTests.swift:238-313` (delete the `MotionTests` class)

**Interfaces:**
- Consumes: everything from Tasks 2 and 3.
- Produces: a complete `RevealTimeline.sample(...)`. `SettleTimeline` and `SettleSample` no longer exist. `MotionTiming` keeps only `scrimIn`, `scrimOut`, `toastIn`, `toastHold`, `toastOut`, `reduceMotionCrossfade`, and gains `skipCrossfade: Double = 0.12`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/PostcodeNowCoreTests/RevealTimelineTests.swift`:

```swift
final class BloomAndWashTests: XCTestCase {
    private func sample(at elapsed: Double) -> RevealSample {
        RevealTimeline.sample(
            elapsed: elapsed,
            searchLoop: 0.5,
            handoffLoop: 0.5,
            outcodeCount: 2,
            incodeCount: 3,
            reduceMotion: false
        )
    }

    func testTheLineStretchesOutOfTheLockBeforeAnyCharacterMoves() {
        let beforeStretch = sample(at: RevealTiming.stretchStart - 0.01)
        XCTAssertEqual(beforeStretch.lineLength, 0, accuracy: 0.001)

        let stretched = sample(at: RevealTiming.bloomStart)
        XCTAssertEqual(stretched.lineLength, 1, accuracy: 0.01)
        XCTAssertGreaterThan(stretched.lineOpacity, 0.5)

        // Nothing has bloomed yet at the instant the line completes.
        XCTAssertEqual(stretched.characters[0].opacity, 0, accuracy: 0.02)
    }

    func testCharactersArriveInOrderWithABeatBetweenTheHalves() {
        let justAfterFirst = sample(at: RevealTiming.bloomStart + 0.03)
        XCTAssertGreaterThan(justAfterFirst.characters[0].opacity, 0)
        XCTAssertEqual(justAfterFirst.characters[4].opacity, 0, accuracy: 0.001)

        // Inside the beat, the outcode has started but the incode has not.
        let duringBeat = sample(
            at: RevealTiming.characterStart(index: 2, outcodeCount: 2) - 0.01
        )
        XCTAssertGreaterThan(duringBeat.characters[1].opacity, 0)
        XCTAssertEqual(duringBeat.characters[2].opacity, 0, accuracy: 0.001)
    }

    func testTheWashStartsAsTheFirstCharacterLandsNotBefore() {
        let beforeWash = sample(at: RevealTiming.washStart - 0.01)
        XCTAssertEqual(beforeWash.washProgress, 0, accuracy: 0.001)

        let washed = sample(at: RevealTiming.washStart + RevealTiming.wash)
        XCTAssertEqual(washed.washProgress, 1, accuracy: 0.001)

        let halfway = sample(at: RevealTiming.washStart + RevealTiming.wash / 2)
        XCTAssertEqual(halfway.washProgress, 0.5, accuracy: 0.02)
    }

    func testTheLineDissolvesOnceTheCodeIsThere() {
        let dissolved = sample(
            at: RevealTiming.lineDissolveStart + RevealTiming.lineDissolve
        )
        XCTAssertEqual(dissolved.lineOpacity, 0, accuracy: 0.001)
    }

    func testTheCTAIsLast() {
        let ctaStart = RevealTiming.ctaStart(outcodeCount: 2, incodeCount: 3)
        XCTAssertEqual(sample(at: ctaStart - 0.01).ctaOpacity, 0, accuracy: 0.001)
        XCTAssertGreaterThan(sample(at: ctaStart + 0.2).ctaOpacity, 0.5)
    }

    func testEverythingLandsExactlySettledAtDuration() {
        let total = RevealTimeline.duration(outcodeCount: 2, incodeCount: 3)
        let settled = RevealSample.settled(outcodeCount: 2, incodeCount: 3)

        XCTAssertEqual(sample(at: total), settled)
        XCTAssertEqual(sample(at: total + 10), settled)
    }

    func testEveryFieldStaysInRangeAcrossTheWholeReveal() {
        let total = RevealTimeline.duration(outcodeCount: 4, incodeCount: 3)
        var time = 0.0
        while time <= total + 0.1 {
            let frame = RevealTimeline.sample(
                elapsed: time,
                searchLoop: 0.5,
                handoffLoop: 0.5,
                outcodeCount: 4,
                incodeCount: 3,
                reduceMotion: false
            )
            for value in [
                frame.lockOpacity, frame.lineOpacity, frame.lineLength,
                frame.washProgress, frame.captionOpacity, frame.wordmarkOpacity,
                frame.sectionOpacity, frame.districtOpacity, frame.ctaOpacity,
                frame.bannerOpacity,
            ] {
                XCTAssertGreaterThanOrEqual(value, 0, "negative at t=\(time)")
                XCTAssertLessThanOrEqual(value, 1, "above 1 at t=\(time)")
            }
            for character in frame.characters {
                XCTAssertGreaterThanOrEqual(character.opacity, 0, "t=\(time)")
                XCTAssertLessThanOrEqual(character.opacity, 1, "t=\(time)")
                XCTAssertGreaterThan(character.scale, 0, "a zero scale collapses the glyph at t=\(time)")
                XCTAssertLessThanOrEqual(character.scale, 1.1, "t=\(time)")
            }
            time += 0.001
        }
    }

    func testOpacitiesOnlyEverIncrease() {
        let total = RevealTimeline.duration(outcodeCount: 2, incodeCount: 3)
        var previous = sample(at: 0)
        var time = 0.001
        while time <= total {
            let frame = sample(at: time)
            XCTAssertGreaterThanOrEqual(
                frame.washProgress, previous.washProgress - 0.0001, "wash reversed at t=\(time)"
            )
            XCTAssertGreaterThanOrEqual(
                frame.ctaOpacity, previous.ctaOpacity - 0.0001, "cta reversed at t=\(time)"
            )
            XCTAssertLessThanOrEqual(
                frame.captionOpacity, previous.captionOpacity + 0.0001, "caption returned at t=\(time)"
            )
            previous = frame
            time += 0.001
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter BloomAndWashTests`
Expected: FAIL — line, character, wash and CTA fields are still at their Act 1 values.

- [ ] **Step 3: Complete the revealing branch**

In `Sources/PostcodeNowCore/RevealTimeline.swift`, replace the `revealing` function entirely:

```swift
    private static func revealing(
        elapsed: Double,
        handoffLoop: Double,
        outcodeCount: Int,
        incodeCount: Int
    ) -> RevealSample {
        let count = max(0, outcodeCount + incodeCount)
        let total = RevealTiming.duration(outcodeCount: outcodeCount, incodeCount: incodeCount)
        if elapsed >= total {
            return .settled(outcodeCount: outcodeCount, incodeCount: incodeCount)
        }

        // Act 2 — the rings collapse from wherever they were into the lock.
        let collapse = Easing.easeInOutCubic(
            Easing.unit(elapsed, start: 0, duration: RevealTiming.collapse)
        )
        let frozen = scanRings(loop: handoffLoop)
        let rings = frozen.map { ring in
            RingState(
                radius: ring.radius + (RevealTiming.lockRadius - ring.radius) * collapse,
                opacity: ring.opacity * (1 - collapse),
                lineWidth: ring.lineWidth
            )
        }
        let contraction = Easing.easeOutBack(
            Easing.unit(elapsed, start: RevealTiming.collapse, duration: 0.17)
        )

        // Act 3 — the lock stretches into a line, then emits the characters.
        let stretch = Easing.easeInOutCubic(
            Easing.unit(elapsed, start: RevealTiming.stretchStart, duration: RevealTiming.stretch)
        )
        let lineFade = Easing.easeInCubic(
            Easing.unit(
                elapsed,
                start: RevealTiming.lineDissolveStart,
                duration: RevealTiming.lineDissolve
            )
        )
        let characters = (0..<count).map { index -> CharacterState in
            let start = RevealTiming.characterStart(index: index, outcodeCount: outcodeCount)
            let spring = Easing.clamp01(
                SpringCurve.value(
                    response: RevealTiming.characterResponse,
                    dampingFraction: RevealTiming.characterDamping,
                    time: elapsed - start
                )
            )
            return CharacterState(
                opacity: spring,
                offsetY: 14 * (1 - spring),
                scale: 0.86 + 0.14 * spring,
                weightBlend: spring
            )
        }

        // Act 4 — the colour the characters emit, then the labels and the CTA.
        let wash = Easing.easeInOutCubic(
            Easing.unit(elapsed, start: RevealTiming.washStart, duration: RevealTiming.wash)
        )
        let label = Easing.easeOutCubic(
            Easing.unit(elapsed, start: RevealTiming.labelStart, duration: RevealTiming.label)
        )
        let banner = Easing.easeOutCubic(
            Easing.unit(elapsed, start: RevealTiming.bannerStart, duration: RevealTiming.banner)
        )
        let cta = Easing.clamp01(
            SpringCurve.value(
                response: RevealTiming.ctaResponse,
                dampingFraction: RevealTiming.ctaDamping,
                time: elapsed - RevealTiming.ctaStart(
                    outcodeCount: outcodeCount,
                    incodeCount: incodeCount
                )
            )
        )

        return RevealSample(
            rings: rings,
            lockRadius: RevealTiming.lockRadius
                + (RevealTiming.lockContracted - RevealTiming.lockRadius) * contraction,
            lockOpacity: collapse * (1 - stretch),
            lineLength: stretch,
            lineThickness: 2 * stretch,
            lineOpacity: stretch * (1 - lineFade),
            characters: characters,
            washProgress: wash,
            captionOpacity: 1 - Easing.easeOutCubic(
                Easing.unit(elapsed, start: 0, duration: RevealTiming.captionOut)
            ),
            wordmarkOpacity: 1,
            sectionOpacity: label,
            districtOpacity: label,
            districtOffset: 3 * (1 - label),
            ctaOpacity: cta,
            ctaOffset: 10 * (1 - cta),
            bannerOpacity: banner
        )
    }
```

Note `SpringCurve.value` is `internal` in the existing code and `RevealTimeline` is in the same module, so no access change is needed.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter BloomAndWashTests`
Expected: PASS, 8 tests. `testEverythingLandsExactlySettledAtDuration` depends on the early return matching `.settled` exactly — if it fails, the early return is missing or `RevealSample.settled` disagrees with the final frame.

- [ ] **Step 5: Retire `SettleTimeline` and the constants only it used**

```bash
git rm Sources/PostcodeNowCore/SettleTimeline.swift
```

Replace `Sources/PostcodeNowCore/MotionTiming.swift` entirely:

```swift
import Foundation

/// Durations for everything that is not the reveal itself. The reveal's own
/// timings live in RevealTiming.
public enum MotionTiming {
    public static let scrimIn: Double = 0.18
    public static let scrimOut: Double = 0.16
    public static let toastIn: Double = 0.16
    public static let toastHold: Double = 1.2
    public static let toastOut: Double = 0.14
    public static let reduceMotionCrossfade: Double = 0.08
    /// How long the tap-to-skip crossfade takes. Short enough to feel like a
    /// skip, long enough not to read as a glitch.
    public static let skipCrossfade: Double = 0.12
    /// Edge screens (permission, failure, unsupported) entering and swapping.
    public static let edgeIn: Double = 0.24
    public static let edgeStagger: Double = 0.05
    public static let edgeCrossfade: Double = 0.20
}
```

Delete the entire `MotionTests` class from `Tests/PostcodeNowCoreTests/PostcodeNowCoreTests.swift` (lines 238–313, from `final class MotionTests: XCTestCase {` through its closing brace). Its coverage now lives in `RevealTimingTests` and `RevealTimelineTests`.

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: PASS. The app target does not build yet — `PlaceExperience.swift` still references `SettleTimeline`. That is expected and Task 7 fixes it; do not patch the app target here.

- [ ] **Step 7: Commit**

```bash
git add -A Sources/PostcodeNowCore Tests/PostcodeNowCoreTests
git commit -m "$(cat <<'EOF'
Complete the reveal timeline and retire SettleTimeline

Acts 3 and 4: the lock stretches into a line, the line emits the
characters on staggered springs, and the wash follows the first landing.
The CTA comes last, derived from when the code finishes.

The timeline now returns exactly .settled past its duration, which is
what makes tap-to-skip and Reduce Motion the same code path.

MotionTiming keeps only what is not the reveal. The app target does not
build until the canvas lands.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Declared haptic cues

The existing `LockTick` watches `elapsed` cross one threshold from inside a view. With a haptic per character that does not scale and cannot be tested. The timeline declares its cues instead.

**Files:**
- Create: `Sources/PostcodeNowCore/HapticCue.swift`
- Modify: `Sources/PostcodeNowCore/RevealTimeline.swift` (add `hapticCues`)
- Modify: `Tests/PostcodeNowCoreTests/RevealTimelineTests.swift` (append)

**Interfaces:**
- Consumes: `RevealTiming.*`.
- Produces: `HapticStyle` (`.rigid`, `.soft`, `.light`), `HapticCue { time: Double, style: HapticStyle }`, `RevealTimeline.hapticCues(outcodeCount:incodeCount:) -> [HapticCue]`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/PostcodeNowCoreTests/RevealTimelineTests.swift`:

```swift
final class HapticCueTests: XCTestCase {
    func testOneLockPlusOnePerCharacter() {
        let cues = RevealTimeline.hapticCues(outcodeCount: 2, incodeCount: 3)
        XCTAssertEqual(cues.count, 6)
        XCTAssertEqual(cues.first?.style, .rigid)
        XCTAssertEqual(cues.dropFirst().filter { $0.style == .soft }.count, 5)
    }

    func testCuesAreStrictlyOrdered() {
        for outcodeCount in 2...4 {
            let cues = RevealTimeline.hapticCues(outcodeCount: outcodeCount, incodeCount: 3)
            for pair in zip(cues, cues.dropFirst()) {
                XCTAssertLessThan(pair.0.time, pair.1.time, "cues out of order")
            }
        }
    }

    func testEveryCueLandsInsideTheReveal() {
        for outcodeCount in 2...4 {
            let total = RevealTimeline.duration(outcodeCount: outcodeCount, incodeCount: 3)
            for cue in RevealTimeline.hapticCues(outcodeCount: outcodeCount, incodeCount: 3) {
                XCTAssertGreaterThanOrEqual(cue.time, 0)
                XCTAssertLessThanOrEqual(cue.time, total, "a cue would fire after the reveal ended")
            }
        }
    }

    func testTheLockFiresBeforeAnyCharacter() {
        let cues = RevealTimeline.hapticCues(outcodeCount: 2, incodeCount: 3)
        XCTAssertEqual(cues[0].time, RevealTiming.lockHaptic, accuracy: 0.0001)
        XCTAssertGreaterThan(cues[1].time, RevealTiming.bloomStart)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter HapticCueTests`
Expected: FAIL — `HapticCue` is not defined.

- [ ] **Step 3: Write the cue types and schedule**

Create `Sources/PostcodeNowCore/HapticCue.swift`:

```swift
import Foundation

public enum HapticStyle: String, Equatable, Sendable {
    case rigid
    case soft
    case light
}

/// A haptic the reveal promises to fire at a known time. Declaring these in
/// the timeline rather than detecting them in a view makes their order,
/// count and bounds testable.
public struct HapticCue: Equatable, Sendable {
    public var time: Double
    public var style: HapticStyle

    public init(time: Double, style: HapticStyle) {
        self.time = time
        self.style = style
    }
}
```

Append to `enum RevealTimeline` in `Sources/PostcodeNowCore/RevealTimeline.swift`:

```swift
    /// One firm impact as the rings lock, then one soft impact as each
    /// character lands, so the code arrives in the hand as well as the eye.
    public static func hapticCues(outcodeCount: Int, incodeCount: Int) -> [HapticCue] {
        let count = max(0, outcodeCount + incodeCount)
        var cues = [HapticCue(time: RevealTiming.lockHaptic, style: .rigid)]
        for index in 0..<count {
            let start = RevealTiming.characterStart(index: index, outcodeCount: outcodeCount)
            cues.append(
                HapticCue(time: start + RevealTiming.characterLand, style: .soft)
            )
        }
        return cues
    }
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter HapticCueTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/PostcodeNowCore/HapticCue.swift \
        Sources/PostcodeNowCore/RevealTimeline.swift \
        Tests/PostcodeNowCoreTests/RevealTimelineTests.swift
git commit -m "$(cat <<'EOF'
Declare the reveal's haptics in the timeline

LockTick detected one threshold crossing from inside a view, which does
not scale to a haptic per character and cannot be tested.

The timeline now publishes its cues, so their order, count and bounds
are facts the suite checks rather than behaviour you have to feel.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Per-character hero layout

Spec Risk 1, and the reason it is built before the canvas. Animating characters individually means laying them out individually, which can drift from the width `HeroFitting` measured for the whole string and break Dynamic Type fitting at large sizes. This task proves the widths agree before anything depends on them.

**Files:**
- Create: `Sources/PostcodeNowCore/HeroMetrics.swift`
- Modify: `PostcodeNow/HeroFitting.swift`
- Create: `Tests/PostcodeNowCoreTests/HeroMetricsTests.swift`

**Interfaces:**
- Consumes: `HeroType.tracking`, `HeroType.maxPointSize`, `HeroType.basePointSize(characterCount:)` — all existing.
- Produces: `HeroMetrics.totalWidth(advances:tracking:) -> Double` and `HeroMetrics.offsets(advances:tracking:) -> [Double]` in Core. In the app target, `HeroFitting.characterAdvances(text:size:) -> [CGFloat]` alongside the existing `HeroFitting.pointSize(text:availableWidth:scaledPreference:)`, whose signature does not change.

- [ ] **Step 1: Write the failing test**

Create `Tests/PostcodeNowCoreTests/HeroMetricsTests.swift`:

```swift
import Foundation
import XCTest
@testable import PostcodeNowCore

final class HeroMetricsTests: XCTestCase {
    func testTotalWidthIsAdvancesPlusTrackingBetweenThem() {
        let advances = [10.0, 20.0, 30.0]
        // Tracking sits between characters, so three glyphs have two gaps.
        XCTAssertEqual(
            HeroMetrics.totalWidth(advances: advances, tracking: 2),
            64,
            accuracy: 0.0001
        )
    }

    func testSingleCharacterHasNoTracking() {
        XCTAssertEqual(
            HeroMetrics.totalWidth(advances: [42], tracking: 5),
            42,
            accuracy: 0.0001
        )
    }

    func testEmptyIsZero() {
        XCTAssertEqual(HeroMetrics.totalWidth(advances: [], tracking: 5), 0, accuracy: 0.0001)
    }

    func testOffsetsStartAtZeroAndAccumulate() {
        let offsets = HeroMetrics.offsets(advances: [10, 20, 30], tracking: 2)
        XCTAssertEqual(offsets, [0, 12, 34])
    }

    /// The invariant that keeps per-character layout agreeing with the width
    /// HeroFitting measured for the whole string.
    func testLastOffsetPlusLastAdvanceEqualsTotalWidth() {
        let advances = [11.5, 9.25, 30.0, 14.75, 8.0]
        let tracking = HeroType.tracking
        let offsets = HeroMetrics.offsets(advances: advances, tracking: tracking)
        XCTAssertEqual(
            offsets.last! + advances.last!,
            HeroMetrics.totalWidth(advances: advances, tracking: tracking),
            accuracy: 0.0001
        )
    }

    /// Review Focus 3: GIR 0AA is seven characters with a three-letter
    /// outcode, and it must lay out like any other postcode.
    func testGiroLaysOutAsSevenCharacters() {
        let advances = Array(repeating: 40.0, count: 7)
        let offsets = HeroMetrics.offsets(advances: advances, tracking: HeroType.tracking)
        XCTAssertEqual(offsets.count, 7)
        XCTAssertEqual(
            offsets.last! + 40.0,
            HeroMetrics.totalWidth(advances: advances, tracking: HeroType.tracking),
            accuracy: 0.0001
        )
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter HeroMetricsTests`
Expected: FAIL — `HeroMetrics` is not defined.

- [ ] **Step 3: Write the metrics**

Create `Sources/PostcodeNowCore/HeroMetrics.swift`:

```swift
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter HeroMetricsTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Expose per-character advances from `HeroFitting`**

Replace `PostcodeNow/HeroFitting.swift` entirely. `pointSize` keeps its exact behaviour and signature; `characterAdvances` is new and shares the same font construction, which is what keeps the two in agreement:

```swift
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

    private static func measuredWidth(_ text: String, size: Double) -> Double {
        let raw = (text as NSString).size(withAttributes: [.font: heroFont(size: size)]).width
        let tracking = HeroType.tracking * Double(max(text.count - 1, 0))
        return Double(raw) + tracking
    }
}
```

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: PASS. `HeroFitting` is in the app target and is not covered by the SPM suite; Step 7 verifies it on device.

- [ ] **Step 7: Verify the widths agree on a real device at both type extremes**

The app target does not build yet (Task 4 removed `SettleTimeline`, which `PlaceExperience` still imports), so this step is a deferred check. Write it into the task's report as an explicit handoff to Task 7, which performs it:

> After `RevealCanvas` renders, screenshot `SW1A 1AA` at the default Dynamic Type size and again at the largest accessibility size. The postcode must stay on one line, stay inside the 24pt horizontal padding, and be horizontally centred in both. If per-character layout is wider than the fitted whole-string width, the code will clip at the largest size — that is the failure this is looking for.

- [ ] **Step 8: Commit**

```bash
git add Sources/PostcodeNowCore/HeroMetrics.swift \
        PostcodeNow/HeroFitting.swift \
        Tests/PostcodeNowCoreTests/HeroMetricsTests.swift
git commit -m "$(cat <<'EOF'
Add per-character hero metrics

Animating characters individually means laying them out individually,
which can drift from the width HeroFitting measured for the whole string
and clip the postcode at large Dynamic Type sizes.

The arithmetic moves into Core with no UIKit, so "per-character layout
and whole-string measurement agree" is a test. HeroFitting now exposes
per-character advances built from the same font, and pointSize keeps its
exact previous behaviour.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: The unified canvas

One view that is never torn down, rendering every sample-driven layer. This is what makes the transformation continuous instead of a cut. It also restores the app target to building.

**Files:**
- Create: `PostcodeNow/RevealCanvas.swift`
- Modify: `PostcodeNow/PlaceExperience.swift` (hosts the canvas; keeps the non-sample-driven chrome)
- Modify: `PostcodeNow/LocateChrome.swift` (ring rendering leaves; the Reduce Motion indicator stays)

**Interfaces:**
- Consumes: `RevealTimeline.sample(...)`, `RevealSample`, `RevealTiming`, `RevealTimeline.duration(outcodeCount:incodeCount:)`, `HeroFitting.pointSize(...)`, `HeroFitting.characterAdvances(text:size:)`, `HeroMetrics.offsets(advances:tracking:)`, `HeroMetrics.totalWidth(advances:tracking:)`, `ThemeInterpolation.frame(from:to:t:)`.
- Produces: `RevealCanvas`, a `View` and `Animatable` on `elapsed`, initialised as
  `RevealCanvas(elapsed: Double?, searchLoop: Double, handoffLoop: Double, chrome: PlaceTheme, session: PlaceSession, reduceMotion: Bool)`.
  `PlaceExperience` keeps its existing initialiser parameters and gains `elapsed`, `searchLoop` and `handoffLoop`.

- [ ] **Step 1: Write the canvas**

Create `PostcodeNow/RevealCanvas.swift`:

```swift
import PostcodeNowCore
import SwiftUI

/// Every layer the timeline drives, in one view that is never torn down.
/// The ring and the postcode have to share a view identity for the reveal to
/// be continuous — if SwiftUI can remove one and insert the other, the user
/// sees a cut no matter how the timings are tuned.
struct RevealCanvas: View, Animatable {
    var elapsed: Double?
    var searchLoop: Double
    var handoffLoop: Double
    var chrome: PlaceTheme
    var session: PlaceSession
    var reduceMotion: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var scaledHero: CGFloat = 80

    /// Driving `elapsed` as animatable data is what gives the whole reveal a
    /// single clock. `nil` means searching, which is not animated.
    var animatableData: Double {
        get { elapsed ?? 0 }
        set { elapsed = newValue }
    }

    private var postcode: UKPostcode { session.fix.postcode }
    private var heroText: String { postcode.formatted }

    private var sample: RevealSample {
        RevealTimeline.sample(
            elapsed: elapsed,
            searchLoop: searchLoop,
            handoffLoop: handoffLoop,
            outcodeCount: postcode.outcode.count,
            incodeCount: postcode.incode.count,
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
        let frame = sample
        let theme = ThemeInterpolation.frame(
            from: chrome,
            to: session.fix.theme,
            t: frame.washProgress
        )

        GeometryReader { proxy in
            ZStack {
                wash(frame: frame, theme: theme, size: proxy.size)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    stage(frame: frame, theme: theme, width: proxy.size.width)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
    }

    /// The colour the postcode emits. It grows from the hero's baseline
    /// outward, so it reads as coming from the code rather than from the
    /// window. The radius covers the diagonal so the corners fill last.
    private func wash(frame: RevealSample, theme: PlaceTheme, size: CGSize) -> some View {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        return ZStack {
            chrome.primary.color
            Circle()
                .fill(session.fix.theme.primary.color)
                .frame(width: diagonal * 2, height: diagonal * 2)
                .scaleEffect(max(0.001, frame.washProgress))
                .position(x: size.width / 2, y: size.height / 2)
                .opacity(frame.washProgress > 0 ? 1 : 0)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func stage(frame: RevealSample, theme: PlaceTheme, width: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(ProductCopy.nearest)
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(theme.onPrimary.color.opacity(HeroType.mutedOpacity))
                .opacity(frame.sectionOpacity)

            ZStack {
                rings(frame: frame, color: chrome.onPrimary.color)
                line(frame: frame, color: theme.onPrimary.color, width: width)
                characters(frame: frame, color: theme.onPrimary.color, width: width)
            }
            .frame(height: 180)

            if let district = session.fix.district {
                Text(district)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(theme.accent.color)
                    .opacity(frame.districtOpacity)
                    .offset(y: CGFloat(frame.districtOffset))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }

            if elapsed == nil {
                VStack(spacing: 6) {
                    Text(ProductCopy.findingTitle)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(chrome.onPrimary.color)
                    Text(ProductCopy.findingCaption)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(chrome.onPrimary.color.opacity(0.62))
                }
                .multilineTextAlignment(.center)
                .opacity(frame.captionOpacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(ProductCopy.findingTitle). \(ProductCopy.findingCaption)")
            }
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
    }

    private func rings(frame: RevealSample, color: Color) -> some View {
        ZStack {
            ForEach(Array(frame.rings.enumerated()), id: \.offset) { _, ring in
                Circle()
                    .stroke(color.opacity(ring.opacity), lineWidth: CGFloat(ring.lineWidth))
                    .frame(width: CGFloat(ring.radius * 2), height: CGFloat(ring.radius * 2))
            }
            Circle()
                .stroke(color.opacity(frame.lockOpacity * 0.9), lineWidth: 2)
                .frame(
                    width: CGFloat(frame.lockRadius * 2),
                    height: CGFloat(frame.lockRadius * 2)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The lock stretched flat. It becomes the baseline the characters rise
    /// out of, then dissolves once they have arrived.
    private func line(frame: RevealSample, color: Color, width: CGFloat) -> some View {
        let available = max(1, width - 48)
        return Capsule()
            .fill(color.opacity(frame.lineOpacity))
            .frame(
                width: available * CGFloat(frame.lineLength),
                height: max(0.5, CGFloat(frame.lineThickness))
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func characters(frame: RevealSample, color: Color, width: CGFloat) -> some View {
        let available = max(1, width - 48)
        let size = HeroFitting.pointSize(
            text: heroText,
            availableWidth: available,
            scaledPreference: scaledHero
        )
        let advances = HeroFitting.characterAdvances(text: heroText, size: size)
        let total = HeroMetrics.totalWidth(
            advances: advances.map(Double.init),
            tracking: HeroType.tracking
        )
        let offsets = HeroMetrics.offsets(
            advances: advances.map(Double.init),
            tracking: HeroType.tracking
        )
        let glyphs = Array(heroText)

        return ZStack(alignment: .leading) {
            ForEach(glyphs.indices, id: \.self) { index in
                glyph(
                    glyphs[index],
                    state: state(frame: frame, glyphIndex: index),
                    size: size,
                    color: color
                )
                .frame(width: advances[index])
                .offset(x: CGFloat(offsets[index]))
            }
        }
        .frame(width: CGFloat(total), alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ProductCopy.heroLabel(
                postcode: heroText,
                district: session.fix.district
            )
        )
    }

    /// The hero string carries a space between outcode and incode that the
    /// timeline does not animate, so glyph indices and character states are
    /// not the same sequence.
    private func state(frame: RevealSample, glyphIndex: Int) -> CharacterState {
        let glyphs = Array(heroText)
        let spaceIndex = postcode.outcode.count
        if glyphIndex == spaceIndex {
            return CharacterState(opacity: 0, offsetY: 0, scale: 1, weightBlend: 0)
        }
        let animated = glyphIndex < spaceIndex ? glyphIndex : glyphIndex - 1
        guard animated >= 0, animated < frame.characters.count, glyphIndex < glyphs.count else {
            return CharacterState(opacity: 1, offsetY: 0, scale: 1, weightBlend: 1)
        }
        return frame.characters[animated]
    }

    private func glyph(
        _ character: Character,
        state: CharacterState,
        size: CGFloat,
        color: Color
    ) -> some View {
        ZStack {
            Text(String(character))
                .font(.system(size: size, weight: .medium, design: .rounded))
                .opacity(1 - state.weightBlend)
            Text(String(character))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .opacity(state.weightBlend)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
        .scaleEffect(CGFloat(max(0.01, state.scale)))
        .offset(y: CGFloat(state.offsetY))
        .opacity(state.opacity)
    }
}
```

- [ ] **Step 2: Rewrite `PlaceExperience` to host the canvas**

Replace everything in `PostcodeNow/PlaceExperience.swift` from `struct PlaceExperience` through the end of `SettleCanvas` (keep the `#Preview` blocks and `previewSession`, updating their arguments in Step 3):

```swift
import PostcodeNowCore
import SwiftUI

/// Hosts the canvas and everything the timeline does not drive: the buttons,
/// the notice banner, the share scrim, the copied toast.
struct PlaceExperience: View {
    var session: PlaceSession
    var chrome: PlaceTheme
    var reduceMotion: Bool
    var isSharing: Bool
    var toastToken: Int
    var elapsed: Double?
    var searchLoop: Double
    var handoffLoop: Double
    var onShare: () -> Void
    var onCopy: () -> Void
    var onRetry: () -> Void

    private var sample: RevealSample {
        RevealTimeline.sample(
            elapsed: elapsed,
            searchLoop: searchLoop,
            handoffLoop: handoffLoop,
            outcodeCount: session.fix.postcode.outcode.count,
            incodeCount: session.fix.postcode.incode.count,
            reduceMotion: reduceMotion
        )
    }

    private var theme: PlaceTheme {
        ThemeInterpolation.frame(from: chrome, to: session.fix.theme, t: sample.washProgress)
    }

    var body: some View {
        let frame = sample
        let resolved = theme

        ZStack {
            RevealCanvas(
                elapsed: elapsed,
                searchLoop: searchLoop,
                handoffLoop: handoffLoop,
                chrome: chrome,
                session: session,
                reduceMotion: reduceMotion
            )
            VStack(spacing: 0) {
                header(frame: frame, theme: resolved)
                Spacer(minLength: 0)
            }
            Color.black
                .opacity(isSharing ? 0.4 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isSharing)
                .accessibilityHidden(true)
                .animation(
                    .easeOut(duration: isSharing ? MotionTiming.scrimIn : MotionTiming.scrimOut),
                    value: isSharing
                )
            VStack {
                CopiedToast(token: toastToken)
                    .padding(.top, 8)
                Spacer()
            }
        }
        .scaleEffect(isSharing ? 0.98 : 1)
        .animation(
            .easeOut(duration: isSharing ? MotionTiming.scrimIn : MotionTiming.scrimOut),
            value: isSharing
        )
        .safeAreaInset(edge: .bottom, spacing: 16) {
            controls(frame: frame, theme: resolved)
        }
    }

    @ViewBuilder
    private func header(frame: RevealSample, theme: PlaceTheme) -> some View {
        if session.isOutdated || session.quality == .approximate {
            banner(theme: theme)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .opacity(frame.bannerOpacity)
                .accessibilitySortPriority(2)
        } else {
            HStack {
                Text(ProductCopy.wordmark)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.onPrimary.color.opacity(HeroType.mutedOpacity))
                    .opacity(frame.wordmarkOpacity)
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    private func controls(frame: RevealSample, theme: PlaceTheme) -> some View {
        VStack(spacing: 8) {
            if session.isOutdated || session.quality == .approximate {
                PrimaryButton(
                    title: session.isOutdated ? ProductCopy.retry : ProductCopy.tryAgain,
                    fill: theme.accent.color,
                    label: theme.onAccent.color,
                    action: onRetry
                )
                SecondaryFillButton(
                    title: ProductCopy.shareAnyway,
                    foreground: theme.onPrimary.color,
                    action: onShare
                )
            } else {
                PrimaryButton(
                    title: ProductCopy.share,
                    fill: theme.accent.color,
                    label: theme.onAccent.color,
                    action: onShare
                )
                SecondaryTextButton(
                    title: ProductCopy.copy,
                    color: theme.onPrimary.color,
                    action: onCopy
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .opacity(frame.ctaOpacity)
        .offset(y: CGFloat(frame.ctaOffset))
        .allowsHitTesting(frame.ctaOpacity > 0.9)
        .accessibilitySortPriority(1)
    }

    @ViewBuilder
    private func banner(theme: PlaceTheme) -> some View {
        if session.isOutdated {
            NoticeBanner(
                title: ProductCopy.outdatedTitle,
                message: ProductCopy.outdatedBody,
                symbol: "info.circle.fill",
                foreground: theme.onPrimary.color,
                background: bannerFill(theme),
                edge: theme.onPrimary.color.opacity(0.7)
            )
        } else if session.quality == .approximate {
            NoticeBanner(
                title: ProductCopy.weakTitle,
                message: ProductCopy.weakBody,
                symbol: "exclamationmark.circle.fill",
                foreground: theme.onPrimary.color,
                background: bannerFill(theme),
                edge: Color(hex: 0xFF9F0A)
            )
        }
    }

    private func bannerFill(_ theme: PlaceTheme) -> Color {
        theme.primary.isLight ? Color.white.opacity(0.62) : Color.black.opacity(0.28)
    }
}
```

- [ ] **Step 3: Update the previews**

In the same file, add `elapsed`, `searchLoop` and `handoffLoop` to all three `#Preview` blocks. For each existing preview, insert after `toastToken: 0,`:

```swift
        elapsed: RevealTimeline.duration(outcodeCount: 2, incodeCount: 3),
        searchLoop: 0,
        handoffLoop: 0,
```

Then add a fourth preview showing the searching state:

```swift
#Preview("Searching") {
    PlaceExperience(
        session: previewSession(outcode: "M1", incode: "1AE", district: "Manchester"),
        chrome: .locateDark,
        reduceMotion: false,
        isSharing: false,
        toastToken: 0,
        elapsed: nil,
        searchLoop: 0.4,
        handoffLoop: 0,
        onShare: {},
        onCopy: {},
        onRetry: {}
    )
}
```

- [ ] **Step 4: Strip the rings from `LocateChrome`**

`LocateChrome` is still used by `RootView` for the pre-session moment and by Reduce Motion. Replace `PostcodeNow/LocateChrome.swift` entirely:

```swift
import PostcodeNowCore
import SwiftUI

/// The static locate screen. Animated scanning now lives in RevealCanvas;
/// this is what Reduce Motion and the pre-session moment show instead.
struct LocateChrome: View {
    var onPrimary: Color
    var showsBackground: Bool = true
    var background: Color = .black

    var body: some View {
        ZStack {
            if showsBackground {
                background.ignoresSafeArea()
            }
            VStack(spacing: 0) {
                HStack {
                    Text(ProductCopy.wordmark)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(onPrimary.opacity(0.55))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .accessibilityHidden(true)
                Spacer()
            }
            VStack(spacing: 28) {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(onPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 160, height: 160)
                VStack(spacing: 6) {
                    Text(ProductCopy.findingTitle)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(onPrimary)
                    Text(ProductCopy.findingCaption)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(onPrimary.opacity(0.62))
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ProductCopy.findingTitle). \(ProductCopy.findingCaption)")
        }
    }
}
```

- [ ] **Step 5: Build**

Run: `mcp__XcodeBuildMCP__build_sim` with the session defaults already set (project `PostcodeNow.xcodeproj`, scheme `PostcodeNow`, simulator `iPhone 17`).

Expected: SUCCEEDED. `RootView` still passes the old `PlaceExperience` arguments, so fix its call site minimally here — pass `elapsed: RevealTimeline.duration(outcodeCount:incodeCount:)` for the session's postcode, `searchLoop: 0`, `handoffLoop: 0` — just enough to compile. Task 8 replaces that with the real clock.

- [ ] **Step 6: Verify Review Focus 4 — the wash with a banner present**

Use the `#Preview` for "Weak GPS", which renders the approximate-fix banner. Confirm in the Xcode canvas that the hero sits below the banner and the wash still fills the whole screen with no uncovered corner. If the wash leaves a gap, the circle radius in `wash(frame:theme:size:)` is too small — it must cover the full diagonal from centre.

- [ ] **Step 7: Verify Review Focus / Task 6 Step 7 — Dynamic Type at both extremes**

Run the app and screenshot the settled state at the default Dynamic Type size, then change the simulator to the largest accessibility size (Settings → Accessibility → Display & Text Size → Larger Text, slider to maximum) and screenshot again.

Both must show `SW1A 1AA` on one line, inside the horizontal padding, horizontally centred. Use a preview with a four-character outcode to force the widest case.

- [ ] **Step 8: Commit**

```bash
git add PostcodeNow/RevealCanvas.swift \
        PostcodeNow/PlaceExperience.swift \
        PostcodeNow/LocateChrome.swift \
        PostcodeNow/RootView.swift
git commit -m "$(cat <<'EOF'
Render the whole reveal from one canvas

The ring and the postcode now share a view identity. If SwiftUI can
remove one and insert the other, the user sees a cut no matter how the
timings are tuned, so the continuity has to be structural.

RevealCanvas owns every sample-driven layer. PlaceExperience keeps what
the timeline does not drive: buttons, banner, scrim, toast.

The wash grows from the hero outward rather than crossfading the
background, so the colour reads as something the postcode emits.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: One clock in `RootView`, and tap to skip

`RootView` stops switching between locating and place. It drives the search loop, freezes the handoff, runs the reveal, and lets a tap end it early.

**Files:**
- Modify: `PostcodeNow/RootView.swift`

`AppModel` is deliberately untouched. The phase machine is already correct; what was wrong was `RootView` tearing down views on every phase change.

**Interfaces:**
- Consumes: `RevealTimeline.duration(outcodeCount:incodeCount:)`, `RevealTiming.scanLoop`, `MotionTiming.skipCrossfade`, `MotionTiming.edgeCrossfade`, `MotionTiming.reduceMotionCrossfade`, `PlaceExperience(session:chrome:reduceMotion:isSharing:toastToken:elapsed:searchLoop:handoffLoop:onShare:onCopy:onRetry:)` from Task 7.
- Produces: no new public API. `RootView` holds `@State revealElapsed: Double?`, `@State searchLoop: Double`, `@State handoffLoop: Double`, `@State revealToken: Int`, and the private helpers `startSearchLoop()`, `beginReveal(session:)`, `skip(session:)`, `settleIfInterrupted()`, `announceSettled(session:after:)`.

- [ ] **Step 1: Drive the search loop and the reveal from `RootView`**

Replace `PostcodeNow/RootView.swift` entirely:

```swift
import PostcodeNowCore
import SwiftUI

@MainActor
struct RootView: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = AppModel(location: LocationService(), client: .live())

    /// nil while searching; seconds since the fix landed once it has.
    @State private var revealElapsed: Double?
    @State private var searchLoop: Double = 0
    @State private var handoffLoop: Double = 0
    @State private var revealToken = 0

    var body: some View {
        @Bindable var model = model
        let chrome = systemScheme == .dark ? PlaceTheme.locateDark : PlaceTheme.locateLight

        ZStack {
            switch model.phase {
            case .locating:
                searchingCanvas(chrome: chrome)
            case .permissionDenied:
                PermissionScreen(onOpenSettings: { model.openSettings() })
                    .transition(.opacity)
            case .failed(let failure):
                FailureScreen(failure: failure, onRetry: { model.start() })
                    .transition(.opacity)
            case .unsupported:
                UnsupportedScreen(onRetry: { model.start() })
                    .transition(.opacity)
            case .place(let session):
                place(session: session, chrome: chrome)
            }
        }
        .animation(.easeInOut(duration: MotionTiming.edgeCrossfade), value: edgeKey)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(forcedScheme)
        .background {
            SharePresenter(
                isPresented: $model.isSharing,
                text: model.shareText ?? "",
                interfaceStyle: model.systemScheme == .dark ? .dark : .light
            )
        }
        .onAppear {
            model.systemScheme = systemScheme
            model.start()
            startSearchLoop()
        }
        .onChange(of: systemScheme) { _, newValue in
            model.systemScheme = newValue
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.resumeIfNeeded()
                settleIfInterrupted()
            }
        }
        .onChange(of: model.phase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
    }

    /// Searching renders through the same canvas the reveal uses, with a
    /// placeholder session, so the rings are already on screen and in motion
    /// when the real session arrives.
    @ViewBuilder
    private func searchingCanvas(chrome: PlaceTheme) -> some View {
        if reduceMotion {
            LocateChrome(onPrimary: chrome.onPrimary.color, background: chrome.primary.color)
        } else {
            PlaceExperience(
                session: Self.placeholderSession,
                chrome: chrome,
                reduceMotion: false,
                isSharing: false,
                toastToken: 0,
                elapsed: nil,
                searchLoop: searchLoop,
                handoffLoop: handoffLoop,
                onShare: {},
                onCopy: {},
                onRetry: {}
            )
            .allowsHitTesting(false)
        }
    }

    private func place(session: PlaceSession, chrome: PlaceTheme) -> some View {
        PlaceExperience(
            session: session,
            chrome: chrome,
            reduceMotion: reduceMotion,
            isSharing: model.isSharing,
            toastToken: model.toastToken,
            elapsed: revealElapsed,
            searchLoop: searchLoop,
            handoffLoop: handoffLoop,
            onShare: { model.sharePostcode() },
            onCopy: { model.copyPostcode() },
            onRetry: { model.start() }
        )
        .contentShape(Rectangle())
        .onTapGesture { skip(session: session) }
    }

    /// A stand-in so the canvas can exist before a real postcode does. Its
    /// characters are never visible while `elapsed` is nil.
    private static let placeholderSession = PlaceSession(
        fix: PostcodeFix(
            postcode: UKPostcode(outcode: "M1", incode: "1AE")!,
            district: nil,
            theme: .neutral
        ),
        quality: .precise,
        isOutdated: false,
        token: 0
    )

    /// Changes only when we move between edge destinations, so the crossfade
    /// never fires for the locating-to-place handoff, which must be seamless.
    private var edgeKey: Int {
        switch model.phase {
        case .locating, .place: return 0
        case .permissionDenied: return 1
        case .failed: return 2
        case .unsupported: return 3
        }
    }

    private func startSearchLoop() {
        guard !reduceMotion else { return }
        searchLoop = 0
        withAnimation(.linear(duration: RevealTiming.scanLoop).repeatForever(autoreverses: false)) {
            searchLoop = 1
        }
    }

    private func handlePhaseChange(_ phase: Phase) {
        switch phase {
        case .place(let session):
            beginReveal(session: session)
        case .locating:
            revealElapsed = nil
            startSearchLoop()
        default:
            revealElapsed = nil
        }
    }

    private func beginReveal(session: PlaceSession) {
        guard !reduceMotion else {
            revealElapsed = RevealTimeline.duration(
                outcodeCount: session.fix.postcode.outcode.count,
                incodeCount: session.fix.postcode.incode.count
            )
            return
        }
        // Freeze where the rings actually are, so Act 2 starts from there.
        handoffLoop = searchLoop.truncatingRemainder(dividingBy: 1)
        revealToken += 1
        revealElapsed = 0
        withAnimation(
            .linear(
                duration: RevealTimeline.duration(
                    outcodeCount: session.fix.postcode.outcode.count,
                    incodeCount: session.fix.postcode.incode.count
                )
            )
        ) {
            revealElapsed = RevealTimeline.duration(
                outcodeCount: session.fix.postcode.outcode.count,
                incodeCount: session.fix.postcode.incode.count
            )
        }
    }

    private func skip(session: PlaceSession) {
        let total = RevealTimeline.duration(
            outcodeCount: session.fix.postcode.outcode.count,
            incodeCount: session.fix.postcode.incode.count
        )
        guard let current = revealElapsed, current < total else { return }
        withAnimation(.easeOut(duration: MotionTiming.skipCrossfade)) {
            revealElapsed = total
        }
    }

    /// Review Focus 5: SwiftUI does not advance animations in the background,
    /// so a reveal interrupted by a backgrounding would otherwise resume from
    /// a stale value or sit frozen mid-bloom. Landing it settled is the only
    /// honest option — the moment has passed.
    private func settleIfInterrupted() {
        guard case .place(let session) = model.phase, let current = revealElapsed else { return }
        let total = RevealTimeline.duration(
            outcodeCount: session.fix.postcode.outcode.count,
            incodeCount: session.fix.postcode.incode.count
        )
        guard current < total else { return }
        withAnimation(.easeOut(duration: MotionTiming.reduceMotionCrossfade)) {
            revealElapsed = total
        }
    }

    private var forcedScheme: ColorScheme? {
        guard case .place(let session) = model.phase else { return nil }
        return session.fix.theme.primary.isLight ? .light : .dark
    }
}
```

Note the `.id(session.token)` from the old implementation is deliberately gone — it forced a teardown on every new session, which is exactly what makes a continuous reveal impossible.

- [ ] **Step 2: Build and run**

Run: `mcp__XcodeBuildMCP__build_run_sim`
Expected: SUCCEEDED and the app launches.

- [ ] **Step 3: Watch the whole reveal**

Set the simulator location to London (Features → Location → Custom Location, 51.5074 / -0.1278), relaunch, and record with `mcp__XcodeBuildMCP__record_sim_video` across the full sequence.

Check, in order: rings scan while searching; they collapse inward without jumping; the lock holds; it stretches to a line; characters rise left to right with a visible beat between outcode and incode; the colour grows from the code; the district and CTAs arrive last. If the rings jump at the handoff, `handoffLoop` is not being frozen from the live `searchLoop` — check that the repeating animation is actually driving `searchLoop` and not just its target value.

- [ ] **Step 4: Verify tap to skip**

Relaunch, and tap the screen roughly half a second after the postcode starts appearing. The reveal must jump to fully settled over ~0.12s, with the buttons immediately usable. Tapping after it has settled must do nothing.

- [ ] **Step 5: Verify Review Focus 2 — retry mid-reveal**

Set the simulator location to somewhere outside the UK (Features → Location → Custom Location, 48.8566 / 2.3522) so the lookup fails, let it fall to the failure screen, then restore a UK location and tap Retry. The reveal must run from the beginning, with rings scanning first. Do it twice in a row and confirm the second run is identical to the first — no doubled haptics, no reveal starting mid-bloom.

- [ ] **Step 6: Verify Review Focus 5 — backgrounding mid-reveal**

Relaunch, and press Home (Device → Home) while the characters are still arriving. Return to the app. It must show the fully settled state, not a frozen half-bloom and not a restarted reveal.

- [ ] **Step 7: Verify Reduce Motion**

Enable Settings → Accessibility → Motion → Reduce Motion in the simulator, relaunch, and confirm: the static locate indicator while searching, then the postcode fully settled with no animation, with the place colour already applied.

- [ ] **Step 8: Announce the postcode when the reveal settles**

The spec requires VoiceOver to hear the result without the reveal stealing focus mid-flight. Nothing announces it today — a VoiceOver user gets a silent 1.5s and then a changed screen.

Add to `RootView`, and call it from the end of `beginReveal` (and from the Reduce Motion early return, with no delay):

```swift
    /// Spoken once the code has landed. Announcing mid-reveal would interrupt
    /// whatever VoiceOver is already reading and move focus off the user's
    /// place, so it waits for the end.
    private func announceSettled(session: PlaceSession, after delay: Double) {
        let label = ProductCopy.heroLabel(
            postcode: session.fix.postcode.formatted,
            district: session.fix.district
        )
        Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            UIAccessibility.post(notification: .announcement, argument: label)
        }
    }
```

Add `import UIKit` to `RootView.swift`. In `beginReveal`, the Reduce Motion branch calls `announceSettled(session: session, after: 0)`; the animated path calls it with `after:` the same duration it animates over.

- [ ] **Step 9: Verify VoiceOver**

Enable VoiceOver in the simulator (Settings → Accessibility → VoiceOver). Relaunch and confirm:
- Focus is not yanked around while the characters are arriving.
- Once settled, the postcode and district are announced once — not repeatedly, and not once per character.
- Swiping through the settled screen reaches the hero as a single element, then the buttons.

- [ ] **Step 10: Profile the per-frame cost (spec Risk 2)**

`RevealCanvas` computes a sample every frame and `ThemeInterpolation.frame` runs contrast math inside it. On a 120Hz ProMotion device that is 120 contrast evaluations a second, plus per-character layout.

Run the app on the simulator with the FPS display on (Debug → Graphics Quality Override is not enough — use Instruments' Animation Hitches template, or Xcode's Debug Navigator FPS gauge while attached).

The reveal must hold its frame rate with no hitches. If it does not, memoise the travelling-colour decision: `ThemeInterpolation.frame` is called with a `washProgress` that changes continuously, so quantise it to 1/60 steps before passing it in, which collapses the contrast work to at most 60 distinct evaluations per reveal.

Record the measured result in the task's report either way, including the device or simulator it was measured on. A simulator number is weaker evidence than a device one — say which it is.

- [ ] **Step 11: Commit**

```bash
git add PostcodeNow/RootView.swift
git commit -m "$(cat <<'EOF'
Give the reveal one clock and let a tap end it

RootView no longer switches views between locating and place. It drives
the search loop, freezes the loop position at the instant the fix lands,
and runs the reveal from there, so Act 2 starts where Act 1 was.

The .id(session.token) that forced a teardown on every session is gone;
it was the thing making a continuous reveal impossible.

A tap snaps to settled over 0.12s. Backgrounding mid-reveal lands
settled rather than resuming stale, since SwiftUI does not advance
animations in the background and the moment has passed either way.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Fire the declared haptics

**Files:**
- Create: `PostcodeNow/Haptics.swift`
- Modify: `PostcodeNow/Controls.swift` (delete `LockTick`)
- Modify: `PostcodeNow/RevealCanvas.swift` (drive the scheduler)

**Interfaces:**
- Consumes: `RevealTimeline.hapticCues(outcodeCount:incodeCount:)`, `HapticCue`, `HapticStyle`.
- Produces: `HapticScheduler`, an `@Observable`-free reference type with `func advance(to elapsed: Double, cues: [HapticCue])` and `func reset()`.

- [ ] **Step 1: Write the scheduler**

Create `PostcodeNow/Haptics.swift`:

```swift
import PostcodeNowCore
import UIKit

/// Fires each declared cue once as the reveal's clock crosses it.
///
/// A reference type rather than view state on purpose: the canvas is
/// re-evaluated many times per frame and must not re-fire what it already
/// played. `reset()` is what makes a retry start clean instead of replaying
/// or swallowing cues.
final class HapticScheduler {
    private var firedThrough = -1
    private var generators: [HapticStyle: UIImpactFeedbackGenerator] = [:]

    func reset() {
        firedThrough = -1
        prepare()
    }

    func prepare() {
        for style in [HapticStyle.rigid, .soft, .light] where generators[style] == nil {
            let generator = UIImpactFeedbackGenerator(style: style.uiStyle)
            generator.prepare()
            generators[style] = generator
        }
    }

    func advance(to elapsed: Double, cues: [HapticCue]) {
        guard !cues.isEmpty else { return }
        var index = firedThrough + 1
        while index < cues.count, cues[index].time <= elapsed {
            fire(cues[index].style)
            index += 1
        }
        firedThrough = index - 1
    }

    private func fire(_ style: HapticStyle) {
        let generator = generators[style] ?? UIImpactFeedbackGenerator(style: style.uiStyle)
        generators[style] = generator
        DispatchQueue.main.async {
            generator.impactOccurred()
            generator.prepare()
        }
    }
}

private extension HapticStyle {
    var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .rigid: return .rigid
        case .soft: return .soft
        case .light: return .light
        }
    }
}
```

- [ ] **Step 2: Drive it from the canvas**

In `PostcodeNow/RevealCanvas.swift`, add the scheduler as a stored property on `RevealCanvas`, after `var reduceMotion: Bool`:

```swift
    var haptics: HapticScheduler
```

And inside `body`, immediately after `let frame = sample`, add:

```swift
        if let elapsed, !reduceMotion {
            haptics.advance(
                to: elapsed,
                cues: RevealTimeline.hapticCues(
                    outcodeCount: postcode.outcode.count,
                    incodeCount: postcode.incode.count
                )
            )
        }
```

Thread it through: `PlaceExperience` gains `var haptics: HapticScheduler` and passes it to `RevealCanvas`. `RootView` holds `@State private var haptics = HapticScheduler()` and passes it to both `PlaceExperience` call sites. In `RootView.beginReveal`, call `haptics.reset()` immediately before setting `revealElapsed = 0`, and in `handlePhaseChange`'s `.locating` case call `haptics.prepare()`. Update the four `#Preview` blocks in `PlaceExperience.swift` to pass `haptics: HapticScheduler()`.

- [ ] **Step 3: Delete `LockTick`**

Remove the entire `final class LockTick` from the end of `PostcodeNow/Controls.swift`. Nothing references it after Task 7 replaced `SettleCanvas`.

- [ ] **Step 4: Build**

Run: `mcp__XcodeBuildMCP__build_run_sim`
Expected: SUCCEEDED.

- [ ] **Step 5: Verify on hardware**

Haptics do not play in the simulator. If a physical device is available, run on it and confirm one firm tap as the rings lock, then a soft tap per character — five for `M1 1AE`, arriving in rhythm with the glyphs.

If no device is available, verify the logic instead: temporarily add `print("haptic \(style) at \(elapsed)")` inside `fire`, run in the simulator, and confirm the console shows exactly six lines in ascending time order, with the first at ~0.26s. Remove the print before committing.

- [ ] **Step 6: Commit**

```bash
git add PostcodeNow/Haptics.swift \
        PostcodeNow/Controls.swift \
        PostcodeNow/RevealCanvas.swift \
        PostcodeNow/PlaceExperience.swift \
        PostcodeNow/RootView.swift
git commit -m "$(cat <<'EOF'
Fire the reveal's haptics from the declared cues

HapticScheduler plays each cue once as the clock crosses it, and resets
on retry so a second run neither replays nor swallows anything.

LockTick is gone. It fired one impact from inside a view and could not
have carried a haptic per character.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Interaction polish

Restraint everywhere that is not the showpiece. Small, deliberate, and the reason the reveal reads as special by contrast.

**Files:**
- Modify: `PostcodeNow/Controls.swift` (`PressFeedbackStyle`, `CopiedToast`)
- Modify: `PostcodeNow/PlaceExperience.swift` (pulse the hero on copy)

**Interfaces:**
- Consumes: `MotionTiming.toastIn/toastHold/toastOut`.
- Produces: `PressFeedbackStyle` gains scale; `PrimaryButton` fires a `.light` impact on tap. `PlaceExperience` gains a private `@State copyPulse: Bool`.

- [ ] **Step 1: Give buttons a press that moves**

In `PostcodeNow/Controls.swift`, replace `PressFeedbackStyle`:

```swift
struct PressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
```

And in `PrimaryButton`, wrap the action so it carries a haptic:

```swift
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(label)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressFeedbackStyle())
    }
```

- [ ] **Step 2: Pulse the postcode when it is copied**

In `PostcodeNow/PlaceExperience.swift`, add to the struct's properties:

```swift
    @State private var copyPulse = false
```

Apply to the `RevealCanvas` in `body`:

```swift
            RevealCanvas(
                elapsed: elapsed,
                searchLoop: searchLoop,
                handoffLoop: handoffLoop,
                chrome: chrome,
                session: session,
                reduceMotion: reduceMotion,
                haptics: haptics
            )
            .scaleEffect(copyPulse ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: copyPulse)
```

And add to `body`'s modifiers, so the pulse rides the same token the toast does:

```swift
        .onChange(of: toastToken) { _, newValue in
            guard newValue > 0, !reduceMotion else { return }
            copyPulse = true
            Task {
                try? await Task.sleep(nanoseconds: 140_000_000)
                copyPulse = false
            }
        }
```

- [ ] **Step 3: Build and run**

Run: `mcp__XcodeBuildMCP__build_run_sim`
Expected: SUCCEEDED.

- [ ] **Step 4: Verify each interaction**

With the app settled on a postcode:
- Press and hold **Share Postcode** — it must shrink slightly and spring back on release, and the content behind the sheet must scale to 0.98 as the sheet rises (that part landed in Task 7).
- Tap **Copy Postcode** — the toast must drop in from the top *and* the postcode itself must pulse once, so the action visibly belongs to the object.
- Enable Reduce Motion and tap Copy again — the toast must appear without the pulse.

Screenshot the copy moment with `mcp__XcodeBuildMCP__screenshot`.

- [ ] **Step 5: Commit**

```bash
git add PostcodeNow/Controls.swift PostcodeNow/PlaceExperience.swift
git commit -m "$(cat <<'EOF'
Make the small interactions move

Buttons shrink and spring back under the thumb instead of only dimming,
and the primary action carries a light impact.

Copying pulses the postcode itself as the toast lands, so the action
reads as belonging to the thing it acted on rather than to the screen.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Entrance motion for the edge screens

Permission, failure, and unsupported currently appear instantly. The crossfade between them landed in Task 8; this gives each one an entrance.

**Files:**
- Modify: `PostcodeNow/EdgeScreens.swift`

**Interfaces:**
- Consumes: `MotionTiming.edgeIn`, `MotionTiming.edgeStagger`.
- Produces: `EdgeEntrance`, a `ViewModifier` applied by all three screens, used as `.edgeEntrance(index:)`.

- [ ] **Step 1: Add the entrance modifier**

Append to `PostcodeNow/EdgeScreens.swift`:

```swift
/// A short rise and fade, staggered by position, so an edge screen assembles
/// rather than appearing all at once.
struct EdgeEntrance: ViewModifier {
    var index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeOut(duration: MotionTiming.edgeIn)
                        .delay(Double(index) * MotionTiming.edgeStagger)
                ) {
                    shown = true
                }
            }
    }
}

extension View {
    func edgeEntrance(index: Int) -> some View {
        modifier(EdgeEntrance(index: index))
    }
}
```

- [ ] **Step 2: Apply it to all three screens**

In `PermissionScreen`, add `.edgeEntrance(index: 0)` to the icon `ZStack`, `.edgeEntrance(index: 1)` to the `Text(ProductCopy.permissionTitle)`, `.edgeEntrance(index: 2)` to `Text(ProductCopy.locationUsage)`, and `.edgeEntrance(index: 3)` to `Text(ProductCopy.permissionPath)`.

In `FailureScreen`, add `.edgeEntrance(index: 0)` to `Text(title)` and `.edgeEntrance(index: 1)` to `Text(message)`.

In `UnsupportedScreen`, add `.edgeEntrance(index: 0)` to `Text(ProductCopy.unsupportedTitle)` and `.edgeEntrance(index: 1)` to `Text(ProductCopy.unsupportedBody)`.

In all three, add `.edgeEntrance(index: 4)` to the `NeutralChromeButton` inside `safeAreaInset`.

- [ ] **Step 3: Build and verify each screen**

Run: `mcp__XcodeBuildMCP__build_run_sim`

- **Permission:** reset the simulator's privacy settings (Device → Erase All Content and Settings, or `xcrun simctl privacy booted reset location dev.tade.PostcodeNow`), relaunch, and deny location. The screen's elements must arrive in sequence.
- **Failure:** set the simulator location outside the UK and relaunch.
- **Unsupported:** set the location to Belfast (54.5973 / -5.9301) and relaunch.

Screenshot each.

- [ ] **Step 4: Verify Reduce Motion skips the entrance**

With Reduce Motion on, each edge screen must appear fully formed with no rise or stagger.

- [ ] **Step 5: Commit**

```bash
git add PostcodeNow/EdgeScreens.swift
git commit -m "$(cat <<'EOF'
Let the edge screens arrive instead of appearing

Permission, failure and unsupported snapped into existence fully formed.
Each now rises 8pt and fades in, staggered by position, so the screen
assembles. Reduce Motion skips it entirely.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Close the launch seam and update the docs

The first seam anyone sees, and the last cleanup.

**Files:**
- Modify: `PostcodeNow/Info.plist` (`UILaunchScreen`)
- Modify: `README.md`
- Modify: `Tests/PostcodeNowCoreTests/PostcodeNowCoreTests.swift` (the Info.plist contract test)

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new.

- [ ] **Step 1: Give the launch screen a background**

`UILaunchScreen` is an empty dict, so the app flashes white before the first frame. In `PostcodeNow/Info.plist`, replace:

```xml
	<key>UILaunchScreen</key>
	<dict/>
```

with:

```xml
	<key>UILaunchScreen</key>
	<dict>
		<key>UIColorName</key>
		<string>LaunchBackground</string>
	</dict>
```

Then create the colour set `PostcodeNow/Assets.xcassets/LaunchBackground.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0xF7",
          "green" : "0xF2",
          "red" : "0xF2"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0x00",
          "green" : "0x00",
          "red" : "0x00"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

These are `PlaceTheme.locateLight.primary` (`0xF2F2F7`) and `PlaceTheme.locateDark.primary` (`0x000000`), so launch is continuous with Act 1 in both appearances.

- [ ] **Step 2: Extend the Info.plist contract test**

In `Tests/PostcodeNowCoreTests/PostcodeNowCoreTests.swift`, inside `InfoPlistContractTests.testLocationUsageAndDisplayNameMatchTheApp`, append:

```swift
        let launch = try XCTUnwrap(plist["UILaunchScreen"] as? [String: Any])
        XCTAssertEqual(
            launch["UIColorName"] as? String,
            "LaunchBackground",
            "an empty UILaunchScreen flashes white before the first frame"
        )
```

- [ ] **Step 3: Run the suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 4: Verify the launch is continuous**

Run: `mcp__XcodeBuildMCP__build_run_sim`, then record the launch with `mcp__XcodeBuildMCP__record_sim_video` starting before the tap. There must be no white flash between the icon zoom and the scanning rings. Repeat in dark mode (Features → Toggle Appearance).

- [ ] **Step 5: Update the README**

In `README.md`, replace the `## Sequence` section with:

```markdown
## Sequence

1. Scanning rings while Core Location finds you — they loop for as long as it takes.
2. The rings collapse into a lock, stretch into a line, and the postcode rises out of it.
3. The place colour floods out from the code itself.
4. **Share Postcode** opens the system share sheet. **Copy Postcode** copies the code.

A tap during the reveal jumps straight to the settled state. Reduce Motion
shows the settled state from the start.

Every UK outcode has its own colour, derived from the outcode itself and
forced into a contrast-safe band — so a postcode always looks the same, and
neighbouring postcodes look different.
```

Then update the Tests section to name the new files:

```markdown
Postcode parsing, the place palette, the reveal timeline, share text, and the
postcodes.io client live in the `PostcodeNowCore` package:
```

- [ ] **Step 6: Full verification sweep**

Run `swift test` — all green.
Run `mcp__XcodeBuildMCP__build_run_sim` — SUCCEEDED with no warnings.

Then walk the whole app once more at a UK location and confirm, in one recording: launch with no flash → rings scan → seamless collapse → line → characters with the beat → colour from the code → district → CTAs → copy pulses → share scales back.

- [ ] **Step 7: Commit**

```bash
git add PostcodeNow/Info.plist \
        PostcodeNow/Assets.xcassets/LaunchBackground.colorset/Contents.json \
        README.md \
        Tests/PostcodeNowCoreTests/PostcodeNowCoreTests.swift
git commit -m "$(cat <<'EOF'
Close the launch seam and document the reveal

UILaunchScreen was an empty dict, so the app flashed white before its
first frame. It now carries the locate background in both appearances,
making launch continuous with the scanning rings.

The plist contract test covers it, since an empty dict is easy to
reintroduce and the flash is easy to stop noticing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Notes for the executor

- **`swift test` builds only the Core package.** The app target is built with XcodeBuildMCP against `PostcodeNow.xcodeproj`, scheme `PostcodeNow`, simulator `iPhone 17`. Session defaults are already set.
- **The app target does not build between Tasks 4 and 7.** That is intended — Task 4 removes `SettleTimeline` and Task 7 replaces its only consumer. Do not patch the app target in between.
- **Motion is judged by eye, not only by tests.** Several steps ask for a screenshot or a recording. They are not optional; a timeline can be green and still feel wrong, and the whole point of this work is how it feels.
- **If a timing feels wrong on device, change the constant in `RevealTiming` and re-run the suite.** The bounds in `RevealTimingTests` are the contract; the individual constants inside them are yours to tune.
