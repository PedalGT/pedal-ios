import Foundation

/// One place for the values that change between machines and demos.
enum Config {
    /// Apple Pay merchant ID. Must match the entry in Pedal.entitlements and the
    /// merchant ID registered on developer.apple.com (paid account only).
    static let merchantID = "merchant.com.sahilquazi.pedal"

    /// PLACEHOLDER: the published site. Ride links look like
    /// https://<siteHost>/ride/<BIKE_CODE> and open the app (Universal Link).
    /// Must match applinks: in Pedal.entitlements and SITE_URL on the server.
    static let siteHost = "pedalgt-esb6dmewe0bnafbz.westus-01.azurewebsites.net"

    /// When true, a ride can only end after a photo that passes the bike check.
    /// Off while testing without a bike.
    static let requireBikePhotoToEndRide = false

    /// Used before the human sets their own server address in Settings.
    static let defaultBaseURL = "https://pedalgt-esb6dmewe0bnafbz.westus-01.azurewebsites.net"

    /// Georgia Tech, the centre of the bike map.
    static let campusLatitude = 33.7756
    static let campusLongitude = -84.3963

    // Polling intervals, in seconds.
    static let bikeRefreshInterval: TimeInterval = 3
    static let activeRideRefreshInterval: TimeInterval = 5
    static let cardLinkPollInterval: TimeInterval = 2
    static let cardLinkWindow: TimeInterval = 60

    /// Don't hold up an unlock waiting for a GPS fix.
    static let locationTimeout: TimeInterval = 5

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

/// Money is integer cents everywhere. Format only at the edge.
extension Int {
    var asMoney: String {
        let sign = self < 0 ? "-" : ""
        return "\(sign)$\(String(format: "%.2f", Double(abs(self)) / 100))"
    }

    /// "+$5.00" / "-$0.35", for the wallet activity list.
    var asSignedMoney: String {
        (self > 0 ? "+" : "") + asMoney
    }
}
