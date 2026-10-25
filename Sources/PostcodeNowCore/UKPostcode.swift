import Foundation

public struct UKPostcode: Equatable, Hashable, Sendable {
    public var outcode: String
    public var incode: String

    public var formatted: String { "\(outcode) \(incode)" }

    public init?(outcode: String, incode: String) {
        let outward = Self.token(outcode)
        let inward = Self.token(incode)
        if outward == "GIR", inward == "0AA" {
            self.outcode = outward
            self.incode = inward
            return
        }
        guard Self.isOutcode(outward), Self.isIncode(inward) else { return nil }
        self.outcode = outward
        self.incode = inward
    }

    public init?(raw: String) {
        let compact = Self.token(raw)
        guard compact.count >= 5 else { return nil }
        let split = compact.index(compact.endIndex, offsetBy: -3)
        let outward = String(compact[..<split])
        let inward = String(compact[split...])
        self.init(outcode: outward, incode: inward)
    }

    private static func token(_ value: String) -> String {
        value.uppercased().filter { !$0.isWhitespace }
    }

    private static func isOutcode(_ value: String) -> Bool {
        value.range(of: #"^[A-Z]{1,2}\d[A-Z\d]?$"#, options: .regularExpression) != nil
    }

    private static func isIncode(_ value: String) -> Bool {
        value.range(of: #"^\d[A-Z]{2}$"#, options: .regularExpression) != nil
    }
}
