import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return String(localized: "Invalid server URL. Check the settings.")
        case .http(let code): return String(localized: "The server returned an error (HTTP \(code)).")
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
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)) + path) else {
            throw APIError.badURL
        }
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

    func drives(carID: Int, results: Int = 200) async throws -> [Drive] {
        let payload: DrivesPayload = try await get("/api/v1/cars/\(carID)/drives?show=\(results)")
        return payload.drives
    }

    // teslamateapi kan fela på gamla rader med null-värden (scan error) — hämta sidvis och hoppa över trasiga sidor
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

    func charges(carID: Int, results: Int = 100) async throws -> [Charge] {
        let payload: ChargesPayload = try await get("/api/v1/cars/\(carID)/charges?show=\(results)")
        return payload.charges
    }

    func charge(carID: Int, chargeID: Int) async throws -> Charge {
        let payload: ChargePayload = try await get("/api/v1/cars/\(carID)/charges/\(chargeID)")
        return payload.charge
    }
}
