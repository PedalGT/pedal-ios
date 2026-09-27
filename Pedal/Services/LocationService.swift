import Foundation
import CoreLocation

/// One-shot "where am I right now". Never blocks an unlock for long: if the fix
/// doesn't arrive inside Config.locationTimeout, or permission is denied, it
/// returns nil and the caller carries on without coordinates.
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    var isDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Returns nil rather than throwing: a missing location is never a reason
    /// to fail a ride.
    func currentLocation() async -> CLLocationCoordinate2D? {
        if isDenied { return nil }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Give the permission sheet a moment; if the user ignores it the
            // timeout below still fires.
            try? await Task.sleep(for: .milliseconds(400))
            if isDenied { return nil }
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            // Only one request in flight at a time.
            if self.continuation != nil {
                continuation.resume(returning: self.manager.location?.coordinate)
                return
            }
            self.continuation = continuation
            self.manager.requestLocation()

            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Config.locationTimeout))
                guard let self, !Task.isCancelled else { return }
                // Fall back to the last known fix if there is one.
                self.finish(with: self.manager.location?.coordinate)
            }
        }
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: coordinate)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isDenied { finish(with: nil) }
    }
}
