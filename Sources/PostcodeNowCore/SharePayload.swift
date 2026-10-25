import Foundation

public enum SharePayload {
    public static func message(postcode: String, district: String?) -> String {
        let place = district?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if place.isEmpty {
            return "My postcode: \(postcode)"
        }
        return "My postcode: \(postcode), \(place)"
    }

    public static func clipboard(postcode: String) -> String {
        postcode
    }
}
