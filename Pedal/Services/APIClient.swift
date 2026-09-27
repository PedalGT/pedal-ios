import Foundation

/// Errors carry the server's own message where there is one, because
/// docs/API.md says to show `error` to the user as-is.
enum APIError: LocalizedError {
    case badURL(String)
    case unauthorized
    case server(String)
    case notFound(String)
    case offline(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let s):
            return "That server address isn't a valid URL: \(s)"
        case .unauthorized:
            return "Your session expired. Log in again."
        case .server(let message), .notFound(let message):
            return message
        case .offline(let detail):
            return "Can't reach the server. Check the address in Settings and that your phone is on the same network. (\(detail))"
        case .decoding(let detail):
            return "The server sent something unexpected. (\(detail))"
        }
    }
}

/// Every HTTP call in the app goes through here.
final class APIClient {
    /// Posted when the server rejects the token, so AppModel can log out.
    static let unauthorizedNotification = Notification.Name("pedal.unauthorized")

    private let auth: AuthStore
    private let session: URLSession

    init(auth: AuthStore) {
        self.auth = auth
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Core request

    private func request<T: Decodable>(
        _ method: String,
        _ path: String,
        body: [String: Any?]? = nil,
        authorized: Bool = true,
        baseURLOverride: String? = nil
    ) async throws -> T {
        let data = try await raw(method, path, body: body, authorized: authorized, baseURLOverride: baseURLOverride)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    @discardableResult
    private func raw(
        _ method: String,
        _ path: String,
        body: [String: Any?]? = nil,
        authorized: Bool = true,
        baseURLOverride: String? = nil
    ) async throws -> Data {
        let base = AuthStore.normalize(baseURLOverride ?? auth.baseURL)
        guard let url = URL(string: base + path), url.scheme != nil, url.host != nil else {
            throw APIError.badURL(base + path)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        if authorized, let token = auth.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            // Drop nils so optional lat/lng are simply absent rather than null.
            let clean = body.compactMapValues { $0 }
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: clean)
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError {
            throw APIError.offline(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("no HTTP response")
        }

        if http.statusCode == 401 {
            if authorized { NotificationCenter.default.post(name: Self.unauthorizedNotification, object: nil) }
            // Login/signup send 401 too; surface the server's wording there.
            if let body = try? JSONDecoder().decode(ServerErrorBody.self, from: data), !authorized {
                throw APIError.server(body.error)
            }
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerErrorBody.self, from: data))?.error
                ?? "The server returned an error (\(http.statusCode))."
            throw http.statusCode == 404 ? APIError.notFound(message) : APIError.server(message)
        }
        return data
    }

    // MARK: - Health

    func health(baseURLOverride: String? = nil) async throws -> HealthResponse {
        try await request("GET", "/api/health", authorized: false, baseURLOverride: baseURLOverride)
    }

    // MARK: - Auth

    func signUp(name: String, email: String, password: String) async throws -> AuthResponse {
        try await request("POST", "/api/auth/signup",
                          body: ["name": name, "email": email, "password": password],
                          authorized: false)
    }

    func logIn(email: String, password: String) async throws -> AuthResponse {
        try await request("POST", "/api/auth/login",
                          body: ["email": email, "password": password],
                          authorized: false)
    }

    func me() async throws -> MeResponse {
        try await request("GET", "/api/me")
    }

    // MARK: - Ask Pedal

    /// `messages`: the conversation so far, oldest first, ending with the rider's question.
    func askPedal(_ messages: [(role: String, text: String)]) async throws -> AssistantResponse {
        try await request("POST", "/api/assistant", body: [
            "messages": messages.map { ["role": $0.role, "text": $0.text] }
        ])
    }

    // MARK: - Wallet

    func topUp(amountCents: Int, method: String, cardNumber: String? = nil, paymentToken: String? = nil) async throws -> BalanceResponse {
        try await request("POST", "/api/wallet/topup", body: [
            "amountCents": amountCents,
            "method": method,
            "cardNumber": cardNumber,
            "paymentToken": paymentToken
        ])
    }

    func transactions() async throws -> TxnsResponse {
        try await request("GET", "/api/wallet/txns")
    }

    // MARK: - Bikes and rides

    func bikes() async throws -> [Bike] {
        let response: BikesResponse = try await request("GET", "/api/bikes")
        return response.bikes
    }

    func bike(code: String) async throws -> Bike {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clean
        let response: BikeResponse = try await request("GET", "/api/bikes/code/\(encoded)")
        return response.bike
    }

    func startRide(bikeCode: String, lat: Double?, lng: Double?, eventId: String? = nil) async throws -> RideResponse {
        try await request("POST", "/api/rides/start",
                          body: ["bikeCode": bikeCode.uppercased(), "lat": lat, "lng": lng, "eventId": eventId])
    }

    func events() async throws -> EventsResponse {
        try await request("GET", "/api/events")
    }

    func reportIssue(bikeCode: String, summary: String, unsafe: Bool) async throws -> BikeIssueResponse {
        try await request("POST", "/api/bikes/\(bikeCode)/issues", body: ["summary": summary, "unsafe": unsafe])
    }

    func resolveIssue(bikeId: String, issueId: String) async throws -> BikeIssueResponse {
        try await request("POST", "/api/owner/bikes/\(bikeId)/issues/\(issueId)/resolve")
    }

    func armEventPass(eventId: String) async throws -> EventPassResponse {
        try await request("POST", "/api/events/\(eventId)/pass")
    }

    func cancelEventPass() async throws -> EventPassResponse {
        try await request("DELETE", "/api/events/pass")
    }

    func endRide(lat: Double?, lng: Double?, photoCheck: [String: Any]? = nil) async throws -> RideResponse {
        try await request("POST", "/api/rides/end", body: ["lat": lat, "lng": lng, "photoCheck": photoCheck])
    }

    func rideHistory() async throws -> [Ride] {
        let response: RideHistoryResponse = try await request("GET", "/api/rides/history")
        return response.rides
    }

    // MARK: - Keycards

    func startCardLink() async throws -> CardLinkResponse {
        try await request("POST", "/api/cards/link-start")
    }

    func unlinkCard() async throws -> User {
        let response: UserResponse = try await request("POST", "/api/cards/unlink")
        return response.user
    }

    // MARK: - Owner

    func listBike(name: String, kind: String, color: String?, perMinuteCents: Int, lat: Double?, lng: Double?) async throws -> Bike {
        let response: BikeResponse = try await request("POST", "/api/owner/bikes", body: [
            "name": name, "kind": kind, "color": color, "perMinuteCents": perMinuteCents, "lat": lat, "lng": lng
        ])
        return response.bike
    }

    func ownerBikes() async throws -> [Bike] {
        let response: BikesResponse = try await request("GET", "/api/owner/bikes")
        return response.bikes
    }

    func updateBike(id: String, name: String? = nil, perMinuteCents: Int? = nil, status: String? = nil) async throws -> Bike {
        let response: BikeResponse = try await request("PATCH", "/api/owner/bikes/\(id)", body: [
            "name": name, "perMinuteCents": perMinuteCents, "status": status
        ])
        return response.bike
    }
}
