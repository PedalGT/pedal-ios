import SwiftUI
import Observation

/// Session state the whole app reads: who is logged in, their balance, and
/// whether a ride is running. `refresh()` is the single source of truth and is
/// called on launch, on foreground, after every mutation, and on a timer while
/// a ride is active.
@MainActor
@Observable
final class AppModel {
    let auth: AuthStore
    let api: APIClient
    let location = LocationService()

    var me: User?
    var balanceCents: Int = 0
    var activeRide: Ride?
    var pricing: Pricing = .fallback
    /// Rides, distance and CO2 saved, from /api/me.
    var impact: Impact?

    /// Bike to events.
    var events: [CampusEvent] = []
    var eventsSource: String?
    var eventsError: String?
    var eventFlatFareCents = 25
    var eventsPoweredBy: String?
    /// Waiting for the rider to tap their card on any lock for an event ride.
    var eventPass: EventPass?
    /// The ride that just ended; shows the "Ride finished" screen.
    var finishedRide: Ride?

    private let rideActivity = RideActivityController()

    /// Set when a background refresh fails, so a screen can show it without
    /// interrupting what the user is doing.
    var backgroundError: String?

    /// Result of opening a ride link, shown as an alert.
    var rideLinkMessage: String?
    /// A ride link opened while logged out; started right after login.
    private var pendingRideCode: String?
    private var lastRideLinkCode: String?
    private var lastRideLinkAt = Date.distantPast

    private var rideTimer: Task<Void, Never>?

    var isLoggedIn: Bool { auth.isLoggedIn }

    init() {
        let auth = AuthStore()
        self.auth = auth
        self.api = APIClient(auth: auth)
        self.me = auth.user

        NotificationCenter.default.addObserver(
            forName: APIClient.unauthorizedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.logOut() }
        }
    }

    // MARK: - Session

    func signedIn(token: String, user: User) async {
        auth.signIn(token: token, user: user)
        me = user
        await refresh()
        startPendingRideLink()
    }

    func logOut() {
        rideTimer?.cancel()
        rideTimer = nil
        auth.signOut()
        me = nil
        balanceCents = 0
        activeRide = nil
        backgroundError = nil
        rideActivity.endAll()
    }

    #if DEBUG
    /// Screenshot mode (DemoLaunch): sign in with the given demo account.
    func demoSignInIfAsked() async {
        guard !isLoggedIn, let email = DemoLaunch.value("-demoEmail"), let password = DemoLaunch.value("-demoPassword"),
              let response = try? await api.logIn(email: email, password: password) else { return }
        await signedIn(token: response.token, user: response.user)
    }
    #endif

    // MARK: - Bike to events

    func armEventPass(for event: CampusEvent) async throws {
        eventPass = try await api.armEventPass(eventId: event.id).pass
    }

    func cancelEventPass() async {
        _ = try? await api.cancelEventPass()
        eventPass = nil
    }

    /// Loads the picked events and (re)schedules their reminders.
    func loadEvents() async {
        guard isLoggedIn else { return }
        do {
            let response = try await api.events()
            events = response.events
            eventsSource = response.source
            eventFlatFareCents = response.flatFareCents
            eventsPoweredBy = response.poweredBy
            eventsError = response.events.isEmpty ? "No events with a map location in the next two days." : nil
            var askForNotifications = true
            #if DEBUG
            askForNotifications = !DemoLaunch.flag("-demoNoPrompts")
            #endif
            if askForNotifications, await EventNotifier.requestPermission() {
                await EventNotifier.schedule(response.events)
            }
        } catch {
            eventsError = "Couldn't load events. \(error.localizedDescription)"
        }
    }

    // MARK: - Refresh

    @discardableResult
    func refresh() async -> Bool {
        guard auth.isLoggedIn else { return false }
        do {
            let response = try await api.me()
            me = response.user
            auth.update(user: response.user)
            balanceCents = response.balanceCents
            activeRide = response.activeRide
            if let pricing = response.pricing { self.pricing = pricing }
            impact = response.impact
            eventPass = response.eventPass
            backgroundError = nil
            syncRideTimer()
            return true
        } catch APIError.unauthorized {
            logOut()
            return false
        } catch {
            backgroundError = error.localizedDescription
            return false
        }
    }

    /// Poll every 5 s while a ride is active so the ride card stays up to date
    /// (fare, and the ride ending from another device).
    private func syncRideTimer() {
        rideActivity.sync(activeRide)   // Live Activity follows the ride
        if activeRide != nil, rideTimer == nil {
            rideTimer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Config.activeRideRefreshInterval))
                    guard let self, !Task.isCancelled else { return }
                    guard self.activeRide != nil else { return }
                    await self.refresh()
                }
            }
        } else if activeRide == nil {
            rideTimer?.cancel()
            rideTimer = nil
        }
    }

    // MARK: - Ride links

    /// Bike code from a ride link: pedal://ride/CODE or https://<siteHost>/ride/CODE.
    static func rideCode(from url: URL) -> String? {
        let parts: [String]
        if url.scheme == "pedal" {
            guard url.host == "ride" else { return nil }
            parts = url.pathComponents.filter { $0 != "/" }
        } else if url.scheme == "https" || url.scheme == "http" {
            let path = url.pathComponents.filter { $0 != "/" }
            guard path.first == "ride" else { return nil }
            parts = Array(path.dropFirst())
        } else {
            return nil
        }
        guard let raw = parts.first else { return nil }
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        return (4...8).contains(code.count) ? code : nil
    }

    /// Opening a ride link unlocks the bike and starts the ride, no extra taps.
    func handleRideLink(_ url: URL) {
        guard let code = Self.rideCode(from: url) else { return }
        // The same tap can be delivered twice (URL and browsing activity).
        if code == lastRideLinkCode, Date().timeIntervalSince(lastRideLinkAt) < 5 { return }
        lastRideLinkCode = code
        lastRideLinkAt = Date()
        guard isLoggedIn else {
            pendingRideCode = code
            rideLinkMessage = "Log in to start your ride on bike \(code)."
            return
        }
        Task { await startRideFromLink(code) }
    }

    /// Called after login so a link opened while logged out still starts the ride.
    func startPendingRideLink() {
        guard let code = pendingRideCode else { return }
        pendingRideCode = nil
        Task { await startRideFromLink(code) }
    }

    private func startRideFromLink(_ code: String) async {
        if let ride = activeRide {
            rideLinkMessage = ride.bikeCode == code
                ? "Your ride on bike \(code) is already going."
                : "You already have a ride in progress. End it before starting another."
            return
        }
        do {
            try await startRide(bikeCode: code)
            rideLinkMessage = "Ride started on bike \(code). The lock is opening."
        } catch {
            rideLinkMessage = "Couldn't start a ride on bike \(code). \(error.localizedDescription)"
        }
    }

    // MARK: - Rides

    /// Grabs the phone's location first (bounded by Config.locationTimeout) so
    /// the server can record where the bike was picked up.
    func startRide(bikeCode: String, eventId: String? = nil) async throws {
        let coordinate = await location.currentLocation()
        let response = try await api.startRide(bikeCode: bikeCode,
                                               lat: coordinate?.latitude,
                                               lng: coordinate?.longitude,
                                               eventId: eventId)
        activeRide = response.ride
        if let balance = response.balanceCents { balanceCents = balance }
        syncRideTimer()
        await refresh()
    }

    /// Returns the finished ride so the caller can show a summary.
    @discardableResult
    func endRide(photoCheck: BikePhotoResult? = nil) async throws -> Ride {
        let coordinate = await location.currentLocation()
        let response = try await api.endRide(lat: coordinate?.latitude,
                                             lng: coordinate?.longitude,
                                             photoCheck: photoCheck?.serverPayload)
        activeRide = nil
        finishedRide = response.ride
        if let balance = response.balanceCents { balanceCents = balance }
        syncRideTimer()
        await refresh()
        return response.ride
    }

    var canAffordRide: Bool { balanceCents >= pricing.minBalanceToStartCents }
}
