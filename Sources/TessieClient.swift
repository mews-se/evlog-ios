import Foundation

// optional supplementary source — fills in data TeslaMate lacks, such as Supercharger costs
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
        let (data, response) = try await Net.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    func vehicles() async throws -> [TessieVehicle] {
        let payload: TessieVehiclesResponse = try await get("/vehicles")
        return payload.results ?? []
    }

    // a lone vehicle answers even when teslamate carries no VIN to match against
    func vehicle(vin: String?) async throws -> TessieVehicle? {
        let all = try await vehicles()
        if let vin, let match = all.first(where: { $0.vin == vin }) { return match }
        return all.count == 1 ? all.first : nil
    }

    func charges(vin: String, from: Date) async throws -> [TessieCharge] {
        let epoch = Int(from.timeIntervalSince1970)
        let payload: TessieChargesResponse = try await get("/\(vin)/charges?from=\(epoch)")
        return payload.results ?? []
    }

    // costs for teslamate charges that have none, matched on start time
    func missingCosts(for charges: [Charge], vin: String) async throws -> [Int: Double] {
        guard let oldest = charges.map(\.startDate).min() else { return [:] }
        let tessieCharges = try await self.charges(vin: vin, from: oldest.addingTimeInterval(-3600))

        // one tessie charge may match only one teslamate charge - an interrupted
        // session can sit as two processes on the teslamate side
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

// the charging and statistics tabs fill in the same costs, so the fetch lives here
// instead of in both views. the VIN is looked up once per server and car, not on
// every reload
enum TessieCosts {
    private static let vins = VINStore()

    static func load(api: APIClient, carID: Int, token: String, for charges: [Charge]) async -> [Int: Double] {
        // the demo carries its own costs - the key stays idle there
        guard !token.isEmpty, !charges.isEmpty, !api.demo else { return [:] }
        guard let vin = await vins.vin(api: api, carID: carID) else { return [:] }
        return (try? await TessieClient(token: token).missingCosts(for: charges, vin: vin)) ?? [:]
    }
}

private actor VINStore {
    private var cache: [String: String] = [:]

    func vin(api: APIClient, carID: Int) async -> String? {
        let key = "\(api.baseURL)|\(carID)"
        if let known = cache[key] { return known }
        guard let cars = try? await api.cars(),
              let vin = cars.first(where: { $0.carId == carID })?.carDetails?.vin else { return nil }
        cache[key] = vin
        return vin
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
    let vehicleConfig: TessieVehicleConfig?
    let chargeState: TessieChargeState?
}

// the only field read out of the big live blocks - a fact, not moment-to-moment state
struct TessieChargeState: Decodable {
    let lifetimeEnergyUsed: Double?
}

// the configuration block the car reports about itself, raw option-code style values
struct TessieVehicleConfig: Decodable {
    let carType: String?
    let frontDriveUnit: String?
    let rearDriveUnit: String?
    let performancePackage: String?
    let hasLudicrousMode: Bool?
    let hasAirSuspension: Bool?
    let exteriorColor: String?
    let exteriorTrim: String?
    let roofColor: String?
    let wheelType: String?
    let spoilerType: String?
    let headlampType: String?
    let interiorTrimType: String?
    let rearSeatHeaters: Int?
    let hasSeatCooling: Bool?
    let thirdRowSeats: String?
    let chargePortType: String?
    let motorizedChargePort: Bool?
    let driverAssist: String?
    let efficiencyPackage: String?
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
        // tolerates both seconds and milliseconds
        return Date(timeIntervalSince1970: startedAt > 1e12 ? startedAt / 1000 : startedAt)
    }
}
