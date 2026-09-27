import ActivityKit
import Foundation

/// The ride Live Activity (lock screen + Dynamic Island). Shared by the app,
/// which starts and updates it, and the PedalWidgets extension, which draws it.
struct RideActivityAttributes: ActivityAttributes {
    /// What changes during the ride. The timer itself runs on-device from `startDate`.
    struct ContentState: Codable, Hashable {
        var fareCents: Int
        var isEnded: Bool
    }

    var bikeName: String
    var bikeCode: String
    var startDate: Date
    /// Locked at unlock.
    var centsPerMinute: Int
    var isOwnBike: Bool
    /// Set when the ride was started from an event invite.
    var eventName: String?
    var eventFlatFareCents: Int?
}
