import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Ogiltig server-URL. Kontrollera inställningarna."
        case .http(let code): return "Servern svarade med fel (HTTP \(code))."
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
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
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

    func drives(carID: Int, results: Int = 100) async throws -> [Drive] {
        let payload: DrivesPayload = try await get("/api/v1/cars/\(carID)/drives?results=\(results)")
        return payload.drives
    }

    func drive(carID: Int, driveID: Int) async throws -> Drive {
        let payload: DrivePayload = try await get("/api/v1/cars/\(carID)/drives/\(driveID)")
        return payload.drive
    }

    func charges(carID: Int, results: Int = 100) async throws -> [Charge] {
        let payload: ChargesPayload = try await get("/api/v1/cars/\(carID)/charges?results=\(results)")
        return payload.charges
    }

    func charge(carID: Int, chargeID: Int) async throws -> Charge {
        let payload: ChargePayload = try await get("/api/v1/cars/\(carID)/charges/\(chargeID)")
        return payload.charge
    }
}
