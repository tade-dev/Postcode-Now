import Foundation
import XCTest
@testable import PostcodeNowCore

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

    func testDeepThemesArePerceptuallyEven() {
        var lowest = Double.infinity
        var highest = 0.0
        var lowestCode = ""
        var highestCode = ""
        for outcode in everyOutcodeShape() {
            let theme = ProceduralPalette.theme(forOutcode: outcode)
            let luminance = theme.primary.relativeLuminance
            // Pale themes are a deliberately different band; compare like with like.
            guard luminance < 0.4 else { continue }
            if luminance < lowest { lowest = luminance; lowestCode = outcode }
            if luminance > highest { highest = luminance; highestCode = outcode }
        }
        // HSL gave 4.5x. OKLCH holds lightness perceptually, so the spread that
        // survives is only what gamut mapping forced.
        XCTAssertLessThanOrEqual(
            highest / lowest,
            1.7,
            "deep themes still vary too much in brightness: \(lowestCode) \(lowest) vs \(highestCode) \(highest)"
        )
    }

    func testAccentRotationVaries() {
        var rotations = Set<Int>()
        for outcode in everyOutcodeShape() {
            rotations.insert(ProceduralPalette.accentRotation(forOutcode: outcode))
        }
        XCTAssertGreaterThanOrEqual(
            rotations.count,
            3,
            "a fixed accent rotation puts the same accent family on most of the country"
        )
    }

    func testMuddyHuesAreExcluded() {
        for outcode in everyOutcodeShape() {
            let hue = ProceduralPalette.hue(forOutcode: outcode)
            XCTAssertFalse(
                (65.0..<130.0).contains(hue),
                "\(outcode) landed in the muddy olive band at \(hue)"
            )
        }
    }
}
