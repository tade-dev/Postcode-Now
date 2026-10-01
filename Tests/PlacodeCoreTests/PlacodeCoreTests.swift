import Foundation
import XCTest
@testable import PlacodeCore

final class PostcodeTests: XCTestCase {
    func testSplitsSpacedAndCompactForms() {
        let spaced = UKPostcode(raw: "m1 1ae")
        XCTAssertEqual(spaced?.outcode, "M1")
        XCTAssertEqual(spaced?.incode, "1AE")
        XCTAssertEqual(spaced?.formatted, "M1 1AE")

        let compact = UKPostcode(raw: "EC1A1BB")
        XCTAssertEqual(compact?.formatted, "EC1A 1BB")

        let exmouth = UKPostcode(raw: "EX1 1AA")
        XCTAssertEqual(exmouth?.outcode, "EX1")
        XCTAssertEqual(exmouth?.incode, "1AA")
        XCTAssertEqual(HeroType.basePointSize(characterCount: exmouth?.formatted.count ?? 0), 72)
    }

    func testLongFormAndSpecialCase() {
        let london = UKPostcode(outcode: "SW1A", incode: "1AA")
        XCTAssertEqual(london?.formatted, "SW1A 1AA")
        XCTAssertEqual(HeroType.basePointSize(characterCount: london?.formatted.count ?? 0), 64)

        let giro = UKPostcode(raw: "gir 0aa")
        XCTAssertEqual(giro?.outcode, "GIR")
        XCTAssertEqual(giro?.incode, "0AA")
    }

    func testRejectsEmptyAndNonsense() {
        XCTAssertNil(UKPostcode(raw: ""))
        XCTAssertNil(UKPostcode(raw: "NOPE"))
        XCTAssertNil(UKPostcode(raw: "1AE"))
        XCTAssertNil(UKPostcode(outcode: "", incode: "1AE"))
    }

    func testNorthernIrelandStillParses() {
        let belfast = UKPostcode(raw: "BT1 1AA")
        XCTAssertEqual(belfast?.outcode, "BT1")
    }

    func testHeroScale() {
        XCTAssertEqual(HeroType.basePointSize(characterCount: 6), 80)
        XCTAssertEqual(HeroType.basePointSize(characterCount: 5), 80)
        XCTAssertEqual(HeroType.basePointSize(characterCount: 7), 72)
        XCTAssertEqual(HeroType.basePointSize(characterCount: 8), 64)
        XCTAssertEqual(HeroType.basePointSize(characterCount: 9), 64)
        XCTAssertEqual(HeroType.maxPointSize, 84)
        XCTAssertEqual(HeroType.tracking, 0.25)
        XCTAssertEqual(HeroType.mutedOpacity, 0.62)
    }
}

final class PaletteTests: XCTestCase {
    func testManchesterMatchesStudioCrimson() {
        let theme = PlacePalette.resolve(outcode: "m1", district: nil)
        XCTAssertEqual(theme.id, "M1")
        XCTAssertEqual(theme.primary.hex, 0xC41E3A)
        XCTAssertEqual(theme.onPrimary.hex, 0xFFFFFF)
        XCTAssertEqual(theme.accent.hex, 0xF5D76E)
        XCTAssertEqual(theme.onAccent.hex, 0x111111)
        XCTAssertFalse(theme.primary.isLight)
    }

    func testExmouthIsTheLightPlace() {
        let theme = PlacePalette.resolve(outcode: "EX1", district: "East Devon")
        XCTAssertEqual(theme.id, "EX1")
        XCTAssertEqual(theme.primary.hex, 0xE8DCC4)
        XCTAssertEqual(theme.onPrimary.hex, 0x1C1812)
        XCTAssertEqual(theme.accent.hex, 0x1C1812)
        XCTAssertEqual(theme.onAccent.hex, 0xFFFCF5)
        XCTAssertGreaterThan(theme.primary.relativeLuminance, 0.55)
    }

    func testOutcodeBeatsDistrict() {
        let theme = PlacePalette.resolve(outcode: "E1", district: "Manchester")
        XCTAssertEqual(theme.id, "E1")
        XCTAssertEqual(theme.primary.hex, 0x1A1A2E)
    }

    func testDistrictFallbackAndNeutral() {
        XCTAssertEqual(PlacePalette.resolve(outcode: "M20", district: "Manchester").id, "M1")
        XCTAssertEqual(PlacePalette.resolve(outcode: "EH2", district: "City of Edinburgh").id, "EH1")
        XCTAssertEqual(PlacePalette.resolve(outcode: "NE2", district: "Newcastle upon Tyne").id, "NE1")
        XCTAssertEqual(PlacePalette.resolve(outcode: "ZZ9", district: "Nowhere").id, "neutral")
        XCTAssertEqual(PlacePalette.resolve(outcode: "ZZ9", district: nil).primary.hex, 0x111111)
    }

    func testCuratedContrast() {
        XCTAssertEqual(PlacePalette.curated.count, 11)
        let light = PlacePalette.curated.filter(\.primary.isLight)
        XCTAssertEqual(light.map(\.id), ["EX1"])
        for theme in PlacePalette.curated + [.neutral] {
            XCTAssertGreaterThanOrEqual(
                theme.onPrimary.contrast(against: theme.primary),
                4.5,
                theme.id
            )
            XCTAssertGreaterThanOrEqual(
                theme.onAccent.contrast(against: theme.accent),
                4.5,
                "\(theme.id) cta"
            )
        }
    }

    func testWashKeepsContrast() {
        let destinations = [
            PlacePalette.resolve(outcode: "M1", district: nil),
            PlacePalette.resolve(outcode: "EX1", district: nil),
            PlaceTheme.neutral,
        ]
        let origins = [PlaceTheme.locateDark, PlaceTheme.locateLight]
        for origin in origins {
            for destination in destinations {
                for step in stride(from: 0.0, through: 1.0, by: 0.25) {
                    let frame = ThemeInterpolation.frame(from: origin, to: destination, t: step)
                    XCTAssertGreaterThanOrEqual(
                        frame.onPrimary.contrast(against: frame.primary),
                        4.5,
                        "\(origin.id) → \(destination.id) @ \(step)"
                    )
                    XCTAssertGreaterThanOrEqual(
                        frame.onAccent.contrast(against: frame.accent),
                        4.5,
                        "\(origin.id) → \(destination.id) cta @ \(step)"
                    )
                }
                XCTAssertEqual(ThemeInterpolation.frame(from: origin, to: destination, t: 0), origin)
                XCTAssertEqual(ThemeInterpolation.frame(from: origin, to: destination, t: 1), destination)
            }
        }
    }
}

final class ShareAndCopyTests: XCTestCase {
    func testShareMessageIncludesDistrictWhenKnown() {
        XCTAssertEqual(
            SharePayload.message(postcode: "M1 1AE", district: "Manchester"),
            "My postcode: M1 1AE, Manchester"
        )
        XCTAssertEqual(
            SharePayload.message(postcode: "M1 1AE", district: nil),
            "My postcode: M1 1AE"
        )
        XCTAssertEqual(
            SharePayload.message(postcode: "M1 1AE", district: "  "),
            "My postcode: M1 1AE"
        )
    }

    func testClipboardIsThePostcodeOnly() {
        XCTAssertEqual(SharePayload.clipboard(postcode: "M1 1AE"), "M1 1AE")
    }

    func testVoiceOverGroupsTheHero() {
        XCTAssertEqual(
            ProductCopy.heroLabel(postcode: "M1 1AE", district: "Manchester"),
            "Postcode M1 1AE, Manchester. Nearest postcode to your location."
        )
        XCTAssertEqual(
            ProductCopy.heroLabel(postcode: "M1 1AE", district: nil),
            "Postcode M1 1AE. Nearest postcode to your location."
        )
    }

    func testPermissionCopyMatchesTheSpec() {
        XCTAssertEqual(ProductCopy.permissionTitle, "Location is turned off")
        XCTAssertEqual(
            ProductCopy.locationUsage,
            "Placode needs Location to show the nearest UK postcode."
        )
        XCTAssertEqual(
            ProductCopy.permissionPath,
            "Settings → Placode → Location → While Using the App"
        )
        XCTAssertEqual(ProductCopy.weakTitle, "Using approximate location")
        XCTAssertEqual(ProductCopy.weakBody, "Move outdoors for a better fix")
        XCTAssertEqual(ProductCopy.outdatedTitle, "May be outdated")
        XCTAssertEqual(ProductCopy.wordmark, "Placode")
        XCTAssertEqual(ProductCopy.nearest, "Nearest postcode")
    }
}

final class LocationAndRegionTests: XCTestCase {
    func testAccuracyBands() {
        XCTAssertEqual(
            LocationQualityRule.classify(horizontalAccuracy: 12, reducedAccuracy: false),
            .precise
        )
        XCTAssertEqual(
            LocationQualityRule.classify(horizontalAccuracy: 100, reducedAccuracy: false),
            .precise
        )
        XCTAssertEqual(
            LocationQualityRule.classify(horizontalAccuracy: 100.1, reducedAccuracy: false),
            .approximate
        )
        XCTAssertEqual(
            LocationQualityRule.classify(horizontalAccuracy: -1, reducedAccuracy: false),
            .approximate
        )
        XCTAssertEqual(
            LocationQualityRule.classify(horizontalAccuracy: 5, reducedAccuracy: true),
            .approximate
        )
    }

    func testNorthernIrelandIsDeferred() throws {
        let belfast = try XCTUnwrap(UKPostcode(raw: "BT1 1AA"))
        let nearest = NearestPostcode(postcode: belfast, district: "Belfast", country: "Northern Ireland")
        XCTAssertTrue(RegionGate.isDeferred(nearest))
        XCTAssertEqual(LookupResolver.resolve(nearest, quality: .precise), .unsupported)

        let byCountry = NearestPostcode(
            postcode: try XCTUnwrap(UKPostcode(raw: "M1 1AE")),
            district: "Belfast",
            country: "northern ireland"
        )
        XCTAssertEqual(LookupResolver.resolve(byCountry, quality: .precise), .unsupported)
    }

    func testResolverBuildsAPlaceFix() throws {
        let postcode = try XCTUnwrap(UKPostcode(raw: "M1 1AE"))
        let nearest = NearestPostcode(postcode: postcode, district: " Manchester ", country: "England")
        let resolved = LookupResolver.resolve(nearest, quality: .approximate)
        guard case .place(let fix, let quality) = resolved else {
            return XCTFail("expected a place")
        }
        XCTAssertEqual(fix.postcode.formatted, "M1 1AE")
        XCTAssertEqual(fix.district, "Manchester")
        XCTAssertEqual(fix.theme.id, "M1")
        XCTAssertEqual(quality, .approximate)
    }
}

final class MotionTests: XCTestCase {
    func testCookbookConstants() {
        XCTAssertEqual(MotionTiming.locateChromeOut, 0.10)
        XCTAssertEqual(MotionTiming.outcode, 0.12)
        XCTAssertEqual(MotionTiming.beat, 0.05)
        XCTAssertEqual(MotionTiming.incode, 0.14)
        XCTAssertEqual(MotionTiming.incodeResponse, 0.28)
        XCTAssertEqual(MotionTiming.incodeDamping, 0.92)
        XCTAssertEqual(MotionTiming.wash, 0.32)
        XCTAssertEqual(MotionTiming.placeLabelDelay, 0.10)
        XCTAssertEqual(MotionTiming.placeLabel, 0.18)
        XCTAssertEqual(MotionTiming.ctaResponse, 0.32)
        XCTAssertEqual(MotionTiming.ctaDamping, 0.88)
        XCTAssertEqual(MotionTiming.scrimIn, 0.18)
        XCTAssertEqual(MotionTiming.scrimOut, 0.16)
        XCTAssertEqual(MotionTiming.toastIn, 0.16)
        XCTAssertEqual(MotionTiming.toastHold, 1.2)
        XCTAssertEqual(MotionTiming.toastOut, 0.14)
        XCTAssertEqual(MotionTiming.pulseLoop, 1.0)
        XCTAssertLessThanOrEqual(MotionTiming.pulseAmplitude, 0.12)
        XCTAssertLessThanOrEqual(MotionTiming.reduceMotionCrossfade, 0.08)
    }

    func testSignatureStaysInsideTheBudget() {
        XCTAssertEqual(MotionTiming.incodeDelay, 0.17, accuracy: 0.0001)
        XCTAssertEqual(MotionTiming.ctaDelay, 0.31, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(MotionTiming.wash, 0.34)
        XCTAssertGreaterThanOrEqual(MotionTiming.wash, 0.30)
        XCTAssertLessThanOrEqual(MotionTiming.signatureDuration, 0.82)
        XCTAssertLessThanOrEqual(
            SpringCurve.peak(response: MotionTiming.incodeResponse, dampingFraction: MotionTiming.incodeDamping),
            1.015
        )
        XCTAssertLessThanOrEqual(
            SpringCurve.peak(response: MotionTiming.ctaResponse, dampingFraction: MotionTiming.ctaDamping),
            1.015
        )
    }

    func testSettleOrder() {
        let start = SettleTimeline.sample(elapsed: 0)
        XCTAssertEqual(start.locateOpacity, 1, accuracy: 0.001)
        XCTAssertEqual(start.outcodeOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(start.incodeOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(start.wash, 0, accuracy: 0.001)
        XCTAssertEqual(start.ctaOpacity, 0, accuracy: 0.001)

        let outcodeDone = SettleTimeline.sample(elapsed: MotionTiming.outcode)
        XCTAssertEqual(outcodeDone.outcodeOpacity, 1, accuracy: 0.001)
        XCTAssertEqual(outcodeDone.outcodeScale, 1, accuracy: 0.001)
        XCTAssertEqual(outcodeDone.incodeOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(outcodeDone.locateOpacity, 0, accuracy: 0.001)

        let duringBeat = SettleTimeline.sample(elapsed: MotionTiming.incodeDelay - 0.01)
        XCTAssertEqual(duringBeat.incodeOpacity, 0, accuracy: 0.001)

        let incodeMoving = SettleTimeline.sample(elapsed: MotionTiming.incodeDelay + 0.08)
        XCTAssertGreaterThan(incodeMoving.incodeOpacity, 0.4)
        XCTAssertEqual(incodeMoving.ctaOpacity, 0, accuracy: 0.001)

        let washed = SettleTimeline.sample(elapsed: MotionTiming.wash)
        XCTAssertEqual(washed.wash, 1, accuracy: 0.001)

        let halfwayWash = SettleTimeline.sample(elapsed: MotionTiming.wash / 2)
        XCTAssertEqual(halfwayWash.wash, 0.5, accuracy: 0.02)

        let done = SettleTimeline.sample(elapsed: SettleTimeline.duration)
        XCTAssertEqual(done.ctaOpacity, 1, accuracy: 0.02)
        XCTAssertEqual(done.incodeOpacity, 1, accuracy: 0.02)
        XCTAssertEqual(done.placeOpacity, 1, accuracy: 0.001)
        XCTAssertEqual(done.wordmarkOpacity, done.ctaOpacity, accuracy: 0.001)

        XCTAssertEqual(SettleTimeline.sample(elapsed: 0.05, reduceMotion: true), .settled)
    }
}

final class PostcodesAPITests: XCTestCase {
    func testReverseURLIsHTTPSWithoutAKey() throws {
        let url = try PostcodesEndpoint.reverse(latitude: 53.4794, longitude: -2.2453)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.postcodes.io")
        XCTAssertEqual(url.path, "/postcodes")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertTrue(items?.contains(URLQueryItem(name: "limit", value: "1")) == true)
        XCTAssertTrue(items?.contains(URLQueryItem(name: "radius", value: "2000")) == true)
        XCTAssertTrue(items?.contains { $0.name == "lat" } == true)
        XCTAssertTrue(items?.contains { $0.name == "lon" } == true)
        XCTAssertFalse(url.absoluteString.lowercased().contains("key"))
        XCTAssertThrowsError(try PostcodesEndpoint.reverse(latitude: 120, longitude: 0))
    }

    func testDecodesNearestAndIgnoresLaterMatches() async throws {
        let client = PostcodesClient { _ in
            PostcodesClient.HTTPResult(status: 200, data: Data(Self.manchesterFixture.utf8))
        }
        let nearest = try await client.lookup(latitude: 53.48, longitude: -2.24)
        XCTAssertEqual(nearest.postcode.formatted, "M1 1AE")
        XCTAssertEqual(nearest.district, "Manchester")
        XCTAssertEqual(nearest.country, "England")
    }

    func testEmptyResultIsNotFound() async {
        let client = PostcodesClient { _ in
            PostcodesClient.HTTPResult(status: 200, data: Data(#"{"status":200,"result":[]}"#.utf8))
        }
        await assertLookup(client, equals: .notFound)
    }

    func testHTTP404IsNotFound() async {
        let client = PostcodesClient { _ in
            PostcodesClient.HTTPResult(status: 404, data: Data(#"{"status":404,"error":"Postcode not found"}"#.utf8))
        }
        await assertLookup(client, equals: .notFound)
    }

    func testTransportFailureIsOffline() async {
        let client = PostcodesClient { _ in
            throw URLError(.notConnectedToInternet)
        }
        await assertLookup(client, equals: .offline)
    }

    func testMalformedPayloadIsBadResponse() async {
        let client = PostcodesClient { _ in
            PostcodesClient.HTTPResult(status: 200, data: Data("nope".utf8))
        }
        await assertLookup(client, equals: .badResponse)
    }

    private func assertLookup(_ client: PostcodesClient, equals failure: LookupFailure) async {
        do {
            _ = try await client.lookup(latitude: 53.48, longitude: -2.24)
            XCTFail("expected \(failure)")
        } catch let error as LookupFailure {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    private static let manchesterFixture = """
    {
      "status": 200,
      "result": [
        {
          "postcode": "M1 1AE",
          "quality": 1,
          "outcode": "M1",
          "incode": "1AE",
          "admin_district": "Manchester",
          "country": "England",
          "parish": "Manchester, unparished area"
        },
        {
          "postcode": "M1 1AF",
          "outcode": "M1",
          "incode": "1AF",
          "admin_district": "Manchester",
          "country": "England"
        }
      ]
    }
    """
}

final class InfoPlistContractTests: XCTestCase {
    func testLocationUsageAndDisplayNameMatchTheApp() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Placode/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(
            plist["NSLocationWhenInUseUsageDescription"] as? String,
            ProductCopy.locationUsage
        )
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, ProductCopy.wordmark)
        let orientations = try XCTUnwrap(plist["UISupportedInterfaceOrientations"] as? [String])
        XCTAssertEqual(orientations, ["UIInterfaceOrientationPortrait"])
    }
}
