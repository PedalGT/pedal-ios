import ActivityKit
import Foundation

/// Keeps one ride Live Activity in step with `AppModel.activeRide`: starts it when a
/// ride begins (in the app, from a link, or when the app learns of a card tap),
/// updates the fare, and ends it when the ride ends.
@MainActor
final class RideActivityController {
    private var activity: Activity<RideActivityAttributes>?
    private var lastFare: Int?

    init() {
        // Pick up an activity left running from a previous launch.
        activity = Activity<RideActivityAttributes>.activities.first
    }

    func sync(_ ride: Ride?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let ride {
            if let activity, activity.attributes.bikeCode == (ride.bikeCode ?? "") {
                update(fare: ride.fareCents())
            } else {
                endAll()
                start(ride)
            }
        } else if activity != nil {
            end(finalFare: lastFare)
        }
    }

    private func start(_ ride: Ride) {
        let attributes = RideActivityAttributes(
            bikeName: ride.bikeName ?? "Your ride",
            bikeCode: ride.bikeCode ?? "",
            startDate: ride.startDate,
            centsPerMinute: ride.perMinuteCents ?? 0,
            isOwnBike: ride.isFree,
            eventName: ride.event?.name,
            eventFlatFareCents: ride.event?.flatFareCents
        )
        let fare = ride.fareCents()
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: .init(fareCents: fare, isEnded: false), staleDate: nil)
            )
            lastFare = fare
        } catch {
            // Live Activities turned off for Pedal, or too many running: the ride still works.
            activity = nil
        }
    }

    private func update(fare: Int) {
        guard let activity, fare != lastFare else { return }
        lastFare = fare
        Task { await activity.update(ActivityContent(state: .init(fareCents: fare, isEnded: false), staleDate: nil)) }
    }

    private func end(finalFare: Int?) {
        guard let activity else { return }
        let state = RideActivityAttributes.ContentState(fareCents: finalFare ?? 0, isEnded: true)
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 60)) }
        self.activity = nil
        lastFare = nil
    }

    /// Clears any activity that doesn't match the current ride.
    func endAll() {
        for stale in Activity<RideActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
        lastFare = nil
    }
}
