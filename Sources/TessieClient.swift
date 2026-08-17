import Foundation

// valfri kompletterande källa — fyller i data där TeslaMate saknar den, t.ex. Superchargerkostnader
struct TessieClient {
    let token: String

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "https://api.tessie.com" + path) else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    func vehicles() async throws -> [TessieVehicle] {
        let payload: TessieVehiclesResponse = try await get("/vehicles")
        return payload.results ?? []
    }

    func charges(vin: String, from: Date) async throws -> [TessieCharge] {
        let epoch = Int(from.timeIntervalSince1970)
        let payload: TessieChargesResponse = try await get("/\(vin)/charges?from=\(epoch)")
        return payload.results ?? []
    }

    // kostnader för teslamate-laddningar som saknar sådan, matchade på starttid
    func missingCosts(for charges: [Charge], vin: String) async throws -> [Int: Double] {
        guard let oldest = charges.map(\.startDate).min() else { return [:] }
        let tessieCharges = try await self.charges(vin: vin, from: oldest.addingTimeInterval(-3600))

        // en tessie-laddning får bara matcha en teslamate-laddning - en avbruten
        // session kan ligga som två processer på teslamate-sidan
        var pool = tessieCharges.filter { $0.cost ?? 0 > 0 && $0.startDate != nil }
        var costs: [Int: Double] = [:]
        for charge in charges where charge.displayCost == nil {
            guard let idx = pool.indices.min(by: {
                abs(pool[$0].startDate!.timeIntervalSince(charge.startDate)) <
                    abs(pool[$1].startDate!.timeIntervalSince(charge.startDate))
            }) else { continue }
            if let cost = pool[idx].cost, let date = pool[idx].startDate,
               abs(date.timeIntervalSince(charge.startDate)) < 600 {
                costs[charge.chargeId] = cost
                pool.remove(at: idx)
            }
        }
        return costs
    }
}

struct TessieVehiclesResponse: Decodable {
    let results: [TessieVehicle]?
}

struct TessieVehicle: Decodable {
    let vin: String?
    let lastState: TessieVehicleState?
}

struct TessieVehicleState: Decodable {
    let displayName: String?
}

struct TessieChargesResponse: Decodable {
    let results: [TessieCharge]?
}

struct TessieCharge: Decodable {
    let id: Int?
    let startedAt: Double?
    let cost: Double?

    var startDate: Date? {
        guard let startedAt else { return nil }
        // tål både sekunder och millisekunder
        return Date(timeIntervalSince1970: startedAt > 1e12 ? startedAt / 1000 : startedAt)
    }
}
