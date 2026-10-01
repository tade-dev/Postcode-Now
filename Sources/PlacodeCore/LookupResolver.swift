import Foundation

public struct PostcodeFix: Equatable, Sendable {
    public var postcode: UKPostcode
    public var district: String?
    public var theme: PlaceTheme

    public init(postcode: UKPostcode, district: String?, theme: PlaceTheme) {
        self.postcode = postcode
        self.district = district
        self.theme = theme
    }
}

public enum ResolvedLookup: Equatable, Sendable {
    case place(PostcodeFix, quality: LocationQuality)
    case unsupported
}

enum RegionGate {
    static func isDeferred(_ nearest: NearestPostcode) -> Bool {
        if nearest.postcode.outcode.hasPrefix("BT") {
            return true
        }
        return nearest.country?.lowercased() == "northern ireland"
    }
}

public enum LookupResolver {
    public static func resolve(_ nearest: NearestPostcode, quality: LocationQuality) -> ResolvedLookup {
        if RegionGate.isDeferred(nearest) {
            return .unsupported
        }
        let theme = PlacePalette.resolve(
            outcode: nearest.postcode.outcode,
            district: nearest.district
        )
        let fix = PostcodeFix(
            postcode: nearest.postcode,
            district: cleaned(nearest.district),
            theme: theme
        )
        return .place(fix, quality: quality)
    }

    private static func cleaned(_ district: String?) -> String? {
        guard let district else { return nil }
        let trimmed = district.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
