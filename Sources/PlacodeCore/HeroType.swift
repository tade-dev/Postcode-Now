import Foundation

public enum HeroType {
    public static let tracking: Double = 0.25
    public static let maxPointSize: Double = 84
    /// “Nearest postcode” sits at about 62% of onPrimary.
    public static let mutedOpacity: Double = 0.62

    public static func basePointSize(characterCount: Int) -> Double {
        switch characterCount {
        case ...6:
            return 80
        case 7:
            return 72
        default:
            return 64
        }
    }
}
