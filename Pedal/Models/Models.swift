import Foundation
import CoreLocation

// Structs mirror docs/API.md. Fields the server omits on some endpoints are
// optional so one type can decode every shape of the same object.

// MARK: - User

struct User: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let email: String
    /// Georgia Tech ID. nil for accounts made before GTIDs existed.
    let gtid: String?
    /// nil until a keycard is linked.
    let cardUid: String?
}

// MARK: - Pricing

/// Dynamic pricing rules from the server (pricing.js). The live rate for a bike
/// is in `Bike.price`; this is the frame it moves within.
struct Pricing: Codable, Hashable {
    let unlockFeeCents: Int
    let baseCentsPerMinute: Int?
    let minRateCents: Int?
    let maxRateCents: Int?
    let minFareCents: Int?
    let ownerShare: Double
    let minBalanceToStartCents: Int

    static let fallback = Pricing(unlockFeeCents: 0, baseCentsPerMinute: 12, minRateCents: 8, maxRateCents: 20,
                                  minFareCents: 50, ownerShare: 0.8, minBalanceToStartCents: 100)
}

/// One reason a bike costs what it does right now ("Rush hour", ×1.1).
struct PriceFactor: Codable, Hashable {
    let key: String
    let label: String
    let multiplier: Double
}

struct BikePrice: Codable, Hashable {
    let centsPerMinute: Int
    let baseCentsPerMinute: Int?
    let minRateCents: Int?
    let maxRateCents: Int?
    let minFareCents: Int?
    let factors: [PriceFactor]
}

/// A rider's totals: rides, estimated distance and CO2 saved vs driving.
struct Impact: Codable, Hashable {
    let rides: Int
    let distanceKm: Double
    let co2SavedGrams: Int
}

extension Int {
    /// "350 g" / "1.2 kg"
    var asCO2: String {
        self >= 1000 ? String(format: "%.1f kg", Double(self) / 1000) : "\(self) g"
    }
}

// MARK: - Bike

struct Bike: Codable, Identifiable, Hashable {
    let id: String
    let code: String
    let name: String
    let kind: String?
    /// One of BikeColors.all, or nil. Used by the end-of-ride photo check.
    let color: String?
    let status: String
    let unlockFeeCents: Int?
    let perMinuteCents: Int?
    let lastLat: Double?
    let lastLng: Double?
    let lastLocationAt: Double?
    let online: Bool?
    let mine: Bool?
    /// Live dynamic price and why. Locked onto the ride when it starts.
    let price: BikePrice?
    /// Rider views: how many problems riders reported that the owner hasn't fixed.
    let openIssues: Int?
    /// Owner view: the reports themselves.
    let issues: [BikeIssue]?
    let ownerName: String?

    // Owner-only fields, present on /api/owner/bikes.
    let deviceKey: String?
    let rideCount: Int?
    let earnedCents: Int?
    let currentRider: String?

    var isMine: Bool { mine ?? false }
    var isOnline: Bool { online ?? false }
    var isScooter: Bool { kind == "scooter" }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = lastLat, let lng = lastLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var lastLocationDate: Date? {
        lastLocationAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// What a rider sees on the sheet and the fleet list.
    var statusLabel: String {
        switch status {
        case "available": return "Available"
        case "in_use": return currentRider.map { "Being ridden by \($0)" } ?? "Being ridden"
        case "offline": return "Hidden"
        default: return status.capitalized
        }
    }

    var priceLabel: String {
        if isMine { return "Your \(isScooter ? "scooter" : "bike"), free for you" }
        let perMin = price?.centsPerMinute ?? perMinuteCents ?? 12
        if let unlock = unlockFeeCents, unlock > 0 { return "\(unlock.asMoney) to unlock, then \(perMin)¢/min" }
        return "\(perMin)¢/min, no unlock fee"
    }
}

// MARK: - Ride

struct Ride: Codable, Identifiable, Hashable {
    let id: String
    let bikeId: String
    let riderId: String
    let status: String
    let via: String?
    let startAt: Double
    let endAt: Double?
    let startLat: Double?
    let startLng: Double?
    let endLat: Double?
    let endLng: Double?
    let costCents: Int
    let ownerCents: Int
    let minutes: Int
    let bikeName: String?
    let bikeCode: String?
    let bikeColor: String?
    let unlockFeeCents: Int?
    let perMinuteCents: Int?
    /// Dynamic-pricing rides: the fare is at least this (0 for older rides).
    let minFareCents: Int?
    /// Why the rate was what it was when the ride started.
    let priceFactors: [PriceFactor]?
    /// Set when the ride was started from an event invite.
    let event: RideEvent?
    /// True when the ride ended at the event venue and got the flat fare.
    let eventFareApplied: Bool?
    /// Set when the ride ends (estimate vs driving).
    let co2SavedGrams: Int?
    let distanceKm: Double?
    /// Only non-null while the ride is active.
    let liveCostCents: Int?
    let isOwnBike: Bool?

    var isActive: Bool { status == "active" }
    var startDate: Date { Date(timeIntervalSince1970: startAt / 1000) }
    var endDate: Date? { endAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var isFree: Bool { isOwnBike ?? false }

    /// Same formula as the server (pricing.js): locked rate billed by the second,
    /// with a minimum fare. Older rides: unlock fee + ceil(minutes) * per-minute.
    /// Computed locally so the timer's fare updates without a round trip.
    func fareCents(at now: Date = Date()) -> Int {
        if isFree { return 0 }
        let elapsed = max(1, now.timeIntervalSince(startDate))
        let rate = perMinuteCents ?? 12
        if let minFare = minFareCents, minFare > 0 {
            return max(minFare, Int((Double(rate) * elapsed / 60).rounded()))
        }
        let minutes = max(1, Int(ceil(elapsed / 60)))
        return (unlockFeeCents ?? 0) + minutes * rate
    }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(startDate))
    }
}

// MARK: - Transaction

struct Transaction: Codable, Identifiable, Hashable {
    let id: String
    let userId: String?
    let amountCents: Int
    let type: String
    let method: String?
    let rideId: String?
    let note: String?
    let createdAt: Double

    var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }
    var isCredit: Bool { amountCents > 0 }

    var icon: String {
        switch type {
        case "topup": return method == "apple_pay" ? "apple.logo" : "creditcard.fill"
        case "earning": return "arrow.down.circle.fill"
        default: return "bicycle"
        }
    }
}

// MARK: - Responses

struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct MeResponse: Codable {
    let user: User
    let balanceCents: Int
    let activeRide: Ride?
    let pricing: Pricing?
    let impact: Impact?
    let eventPass: EventPass?
}

// MARK: - Bike problems

/// A problem a rider reported (usually through Ask Pedal), for the owner.
struct BikeIssue: Codable, Identifiable, Hashable {
    let id: String
    let summary: String
    let reporterName: String?
    let unsafe: Bool?
    let status: String          // "open" | "resolved"
    let createdAt: Double

    var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }
}

struct BikeIssueResponse: Codable { let issue: BikeIssue }

// MARK: - Bike to events

struct RideEvent: Codable, Hashable {
    let id: String
    let name: String
    let location: String?
    let flatFareCents: Int?
}

/// A real GT event (GT Engage) the AI picked, with an invite line and the
/// nearest free bike.
struct CampusEvent: Codable, Identifiable, Hashable {
    struct NearestBike: Codable, Hashable {
        let code: String
        let name: String
        let meters: Int
    }

    let id: String
    let name: String
    let startsOn: String
    let endsOn: String?
    let location: String
    let organizationName: String?
    let freeFood: Bool
    let invite: String
    let flatFareCents: Int?
    /// What the trip would normally cost from the nearest bike (estimate).
    let usualFareCents: Int?
    let nearestBike: NearestBike?

    var startDate: Date {
        ISO8601DateFormatter().date(from: startsOn) ?? .distantFuture
    }
}

/// Armed from the Events tab: the rider's next card tap on any lock starts a
/// one-time flat-fare ride to this event.
struct EventPass: Codable, Hashable, Identifiable {
    var id: String { eventId }
    let eventId: String
    let eventName: String
    let location: String?
    let flatFareCents: Int
    let expiresAt: Double

    var expiresDate: Date { Date(timeIntervalSince1970: expiresAt / 1000) }
}

struct EventPassResponse: Codable { let pass: EventPass? }

struct EventsResponse: Codable {
    let source: String
    /// "Muse" | "Gemini" | nil when ranked without AI.
    let poweredBy: String?
    let flatFareCents: Int
    let events: [CampusEvent]
}

// MARK: - Ask Pedal

/// Something the assistant suggests. Nothing happens until the rider taps it.
struct AssistantAction: Codable, Hashable {
    let type: String          // "topup" | "start_ride"
    let amountCents: Int?
    let bikeCode: String?
    /// report_issue: what to tell the owner, and whether riding it is dangerous.
    let summary: String?
    let unsafe: Bool?
    let label: String
}

struct AssistantResponse: Codable {
    let reply: String
    let action: AssistantAction?
    let source: String?       // "gemini" | "muse" | "built-in"
    let poweredBy: String?    // "Gemini" | "Muse" | nil
}

struct BikesResponse: Codable { let bikes: [Bike] }
struct BikeResponse: Codable { let bike: Bike }
struct RideResponse: Codable {
    let ride: Ride
    let balanceCents: Int?
}
struct RideHistoryResponse: Codable { let rides: [Ride] }
struct BalanceResponse: Codable { let balanceCents: Int }
struct TxnsResponse: Codable {
    let balanceCents: Int
    let txns: [Transaction]
}
struct CardLinkResponse: Codable {
    let expiresAt: Double
    var expiryDate: Date { Date(timeIntervalSince1970: expiresAt / 1000) }
}
struct UserResponse: Codable { let user: User }
struct HealthResponse: Codable {
    let ok: Bool
    let name: String?
    let time: Double?
}
/// Every 4xx from an app endpoint is `{ "error": "..." }`.
struct ServerErrorBody: Codable { let error: String }
