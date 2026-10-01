import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum LookupFailure: Error, Equatable {
    case offline
    case notFound
    case badResponse
}

public struct NearestPostcode: Equatable, Sendable {
    var postcode: UKPostcode
    var district: String?
    var country: String?
}

enum PostcodesEndpoint {
    static let host = "api.postcodes.io"
    static let radiusMeters = 2_000
    static let limit = 1

    static func reverse(latitude: Double, longitude: Double) throws -> URL {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            throw LookupFailure.badResponse
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/postcodes"
        components.queryItems = [
            URLQueryItem(name: "lat", value: decimal(latitude)),
            URLQueryItem(name: "lon", value: decimal(longitude)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "radius", value: String(radiusMeters)),
        ]
        guard let url = components.url else {
            throw LookupFailure.badResponse
        }
        return url
    }

    private static func decimal(_ value: Double) -> String {
        var text = String(format: "%.6f", value)
        while text.contains("."), text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }
}

public struct PostcodesClient: Sendable {
    struct HTTPResult: Sendable, Equatable {
        var status: Int
        var data: Data
    }

    var transport: @Sendable (URL) async throws -> HTTPResult

    public static func live() -> PostcodesClient {
        let session = configuredSession()
        return PostcodesClient { url in
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return HTTPResult(status: status, data: data)
        }
    }

    public func lookup(latitude: Double, longitude: Double) async throws -> NearestPostcode {
        let url = try PostcodesEndpoint.reverse(latitude: latitude, longitude: longitude)
        let result: HTTPResult
        do {
            result = try await transport(url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw LookupFailure.offline
        }
        switch result.status {
        case 200:
            return try Self.decode(result.data)
        case 404:
            throw LookupFailure.notFound
        default:
            throw LookupFailure.badResponse
        }
    }

    static func decode(_ data: Data) throws -> NearestPostcode {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw LookupFailure.badResponse
        }
        guard envelope.status == 200 else {
            throw LookupFailure.badResponse
        }
        guard let item = envelope.result?.first else {
            throw LookupFailure.notFound
        }
        guard let postcode = postcode(from: item) else {
            throw LookupFailure.badResponse
        }
        return NearestPostcode(
            postcode: postcode,
            district: item.adminDistrict,
            country: item.country
        )
    }

    private static func postcode(from item: ResultItem) -> UKPostcode? {
        if let outcode = item.outcode, let incode = item.incode,
           let parsed = UKPostcode(outcode: outcode, incode: incode) {
            return parsed
        }
        return UKPostcode(raw: item.postcode)
    }

    private static func configuredSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }

    private struct Envelope: Decodable {
        var status: Int
        var result: [ResultItem]?
    }

    private struct ResultItem: Decodable {
        var postcode: String
        var outcode: String?
        var incode: String?
        var adminDistrict: String?
        var country: String?

        enum CodingKeys: String, CodingKey {
            case postcode
            case outcode
            case incode
            case country
            case adminDistrict = "admin_district"
        }
    }
}
