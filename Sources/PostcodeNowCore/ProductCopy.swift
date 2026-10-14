import Foundation

public enum ProductCopy {
    public static let wordmark = "PostcodeNow"
    public static let findingTitle = "Finding your postcode"
    public static let findingCaption = "This only needs location once"
    public static let nearest = "Nearest postcode"
    public static let share = "Share Postcode"
    public static let copy = "Copy Postcode"
    public static let copied = "Copied"
    public static let tryAgain = "Try Again"
    public static let shareAnyway = "Share Anyway"
    public static let retry = "Retry"
    public static let openSettings = "Open Settings"

    public static let permissionTitle = "Location is turned off"
    public static let locationUsage = "PostcodeNow needs Location to show the nearest UK postcode."
    public static let permissionPath = "Settings → PostcodeNow → Location → While Using the App"

    public static let weakTitle = "Using approximate location"
    public static let weakBody = "Move outdoors for a better fix"

    public static let outdatedTitle = "May be outdated"
    public static let outdatedBody = "Showing the last postcode from this session."

    public static let offlineTitle = "No connection"
    public static let offlineBody = "PostcodeNow needs a connection to look up the nearest postcode."

    public static let notFoundTitle = "No postcode nearby"
    public static let notFoundBody = "PostcodeNow couldn't find a UK postcode for this location."

    public static let locationFailTitle = "Couldn't read location"
    public static let locationFailBody = "PostcodeNow couldn't get a location fix. Try again in a moment."

    public static let otherFailTitle = "Something went wrong"
    public static let otherFailBody = "PostcodeNow couldn't look up the nearest postcode."

    public static let unsupportedTitle = "Not available here yet"
    public static let unsupportedBody = "PostcodeNow doesn't cover Northern Ireland postcodes yet."

    public static func heroLabel(postcode: String, district: String?) -> String {
        let place = district?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if place.isEmpty {
            return "Postcode \(postcode). Nearest postcode to your location."
        }
        return "Postcode \(postcode), \(place). Nearest postcode to your location."
    }
}
