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
