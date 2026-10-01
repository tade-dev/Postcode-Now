import CoreLocation
import Foundation

enum LocationServiceError: Error, Equatable {
    case denied
    case unavailable
}

enum LocationAccess: Equatable {
    case authorized
    case denied
}

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<LocationAccess, Never>?
    private var pendingFix: (generation: Int, continuation: CheckedContinuation<CLLocation, Error>)?
    private var nextFixGeneration = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var isReducedAccuracy: Bool {
        manager.accuracyAuthorization == .reducedAccuracy
    }

    var access: LocationAccess {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized
        case .denied, .restricted, .notDetermined:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestFix() async throws -> CLLocation {
        let granted = await ensureAccess()
        try Task.checkCancellation()
        guard granted == .authorized else { throw LocationServiceError.denied }
        nextFixGeneration += 1
        let generation = nextFixGeneration
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let pending = pendingFix {
                    pendingFix = nil
                    pending.continuation.resume(throwing: CancellationError())
                }
                pendingFix = (generation, continuation)
                manager.requestLocation()
            }
        } onCancel: {
            Task { @MainActor in
                guard let pending = self.pendingFix, pending.generation == generation else { return }
                self.pendingFix = nil
                pending.continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func ensureAccess() async -> LocationAccess {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                if let existing = authContinuation {
                    authContinuation = nil
                    existing.resume(returning: .denied)
                }
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return .denied
        }
    }

    private func finishFix(_ result: Result<CLLocation, Error>) {
        guard let pending = pendingFix else { return }
        pendingFix = nil
        pending.continuation.resume(with: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard let continuation = authContinuation else { return }
            switch status {
            case .notDetermined:
                return
            case .authorizedAlways, .authorizedWhenInUse:
                authContinuation = nil
                continuation.resume(returning: .authorized)
            case .denied, .restricted:
                authContinuation = nil
                continuation.resume(returning: .denied)
            @unknown default:
                authContinuation = nil
                continuation.resume(returning: .denied)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            if let location {
                finishFix(.success(location))
            } else {
                finishFix(.failure(LocationServiceError.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in
            if denied {
                finishFix(.failure(LocationServiceError.denied))
            } else {
                finishFix(.failure(LocationServiceError.unavailable))
            }
        }
    }
}
