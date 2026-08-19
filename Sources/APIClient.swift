import Foundation

enum APIError: LocalizedError {
    case noServer
    case noGrafana
    case badURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .noServer: return String(localized: "No server yet. Add your TeslaMate API address under Settings.", bundle: .current)
        case .noGrafana: return String(localized: "No Grafana address yet. Add it under Settings to see this.", bundle: .current)
        case .badURL: return String(localized: "Invalid server URL. Check the settings.", bundle: .current)
        case .http(let code): return String(localized: "The server returned an error (HTTP \(code)).", bundle: .current)
        }
    }
}

struct APIClient {
    let baseURL: String

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        if root.isEmpty { throw APIError.noServer }
        guard let url = URL(string: root + path) else { throw APIError.badURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
        return try Self.decoder.decode(Envelope<T>.self, from: data).data
    }

    func cars() async throws -> [Car] {
        let payload: CarsPayload = try await get("/api/v1/cars")
        return payload.cars
    }

    func status(carID: Int) async throws -> CarStatus {
        let payload: StatusPayload = try await get("/api/v1/cars/\(carID)/status")
        return payload.status
    }

    func updates(carID: Int) async throws -> [SoftwareUpdate] {
        let payload: UpdatesPayload = try await get("/api/v1/cars/\(carID)/updates")
        return payload.updates
    }

    func drives(carID: Int, results: Int = 200) async throws -> [Drive] {
        let payload: DrivesPayload = try await get("/api/v1/cars/\(carID)/drives?show=\(results)")
        return payload.drives
    }

    // teslamateapi can fail on old rows holding nulls (scan error) — page through and skip the broken pages
    func allDrives(carID: Int, pageSize: Int = 500) async throws -> [Drive] {
        var all: [Drive] = []
        var lastError: Error?
        var failures = 0
        var page = 1
        while page <= 40 {
            do {
                let payload: DrivesPayload = try await get("/api/v1/cars/\(carID)/drives?show=\(pageSize)&page=\(page)")
                all += payload.drives
                failures = 0
                if payload.drives.count < pageSize { break }
            } catch {
                lastError = error
                failures += 1
                if failures >= 3 { break }
            }
            page += 1
        }
        if all.isEmpty, let lastError { throw lastError }
        return all
    }

    func drive(carID: Int, driveID: Int) async throws -> Drive {
        let payload: DrivePayload = try await get("/api/v1/cars/\(carID)/drives/\(driveID)")
        return payload.drive
    }

    // plug-ins that never delivered anything have nothing to show and inflate the
    // charge count. TeslaMate's own dashboards drop them the same way
    func charges(carID: Int, results: Int = 100) async throws -> [Charge] {
        let payload: ChargesPayload = try await get("/api/v1/cars/\(carID)/charges?show=\(results)")
        return payload.charges.filter { ($0.chargeEnergyAdded ?? 0) > 0 }
    }

    func charge(carID: Int, chargeID: Int) async throws -> Charge {
        let payload: ChargePayload = try await get("/api/v1/cars/\(carID)/charges/\(chargeID)")
        return payload.charge
    }
}
