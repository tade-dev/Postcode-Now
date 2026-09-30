import PlacodeCore
import SwiftUI
import UIKit

struct PlaceSession: Equatable {
    var fix: PostcodeFix
    var quality: LocationQuality
    var isOutdated: Bool
    var token: Int
}

enum Failure: Equatable {
    case offline
    case notFound
    case location
    case other
}

enum Phase: Equatable {
    case locating
    case permissionDenied
    case failed(Failure)
    case unsupported
    case place(PlaceSession)
}

@MainActor
@Observable
final class AppModel {
    var phase: Phase = .locating
    var isSharing = false
    var toastToken = 0
    var systemScheme: ColorScheme = .light

    private let location: LocationService
    private let client: PostcodesClient
    private var cache: PostcodeFix?
    private var generation = 0
    private var task: Task<Void, Never>?

    init(location: LocationService = LocationService(), client: PostcodesClient = .live()) {
        self.location = location
        self.client = client
    }

    var shareText: String? {
        guard let fix = currentFix else { return nil }
        return SharePayload.message(postcode: fix.postcode.formatted, district: fix.district)
    }

    var currentFix: PostcodeFix? {
        if case .place(let session) = phase {
            return session.fix
        }
        return nil
    }

    func start() {
        generation += 1
        let token = generation
        task?.cancel()
        isSharing = false
        phase = .locating
        task = Task { await run(token: token) }
    }

    func resumeIfNeeded() {
        switch phase {
        case .permissionDenied, .failed(.location):
            if location.access == .authorized {
                start()
            }
        default:
            break
        }
    }

    func sharePostcode() {
        guard shareText != nil else { return }
        isSharing = true
    }

    func copyPostcode() {
        guard let fix = currentFix else { return }
        UIPasteboard.general.string = SharePayload.clipboard(postcode: fix.postcode.formatted)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        toastToken += 1
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func run(token: Int) async {
        do {
            let fix = try await location.requestFix()
            guard token == generation else { return }
            let quality = LocationQualityRule.classify(
                horizontalAccuracy: fix.horizontalAccuracy,
                reducedAccuracy: location.isReducedAccuracy
            )
            let nearest = try await client.lookup(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude
            )
            guard token == generation else { return }
            apply(LookupResolver.resolve(nearest, quality: quality), token: token)
        } catch is CancellationError {
            return
        } catch LocationServiceError.denied {
            guard token == generation else { return }
            phase = .permissionDenied
        } catch LocationServiceError.unavailable {
            guard token == generation else { return }
            phase = .failed(.location)
        } catch LookupFailure.notFound {
            guard token == generation else { return }
            phase = .failed(.notFound)
        } catch LookupFailure.offline {
            guard token == generation else { return }
            showCachedOrFail(.offline, token: token)
        } catch {
            guard token == generation else { return }
            showCachedOrFail(.other, token: token)
        }
    }

    private func apply(_ lookup: ResolvedLookup, token: Int) {
        guard token == generation else { return }
        switch lookup {
        case .unsupported:
            phase = .unsupported
        case .place(let fix, let quality):
            cache = fix
            phase = .place(PlaceSession(fix: fix, quality: quality, isOutdated: false, token: token))
        }
    }

    private func showCachedOrFail(_ failure: Failure, token: Int) {
        guard token == generation else { return }
        if let cache {
            phase = .place(
                PlaceSession(fix: cache, quality: .precise, isOutdated: true, token: token)
            )
        } else {
            phase = .failed(failure)
        }
    }
}
