import Foundation

enum APIError: LocalizedError {
    case noServer
    case noGrafana
    case badURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .noServer: return String(localized: "No server yet. Add your TeslaMate API address under Settings.")
        case .noGrafana: return String(localized: "No Grafana address yet. Add it under Settings to see this.")
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

    // everything since a date, or everything there is when no date is given
    func drives(carID: Int, since: Date? = nil) async throws -> [Drive] {
        try await pages(since: since, start: \.startDate) { page in
            let payload: DrivesPayload = try await get("/api/v1/cars/\(carID)/drives?show=\(Self.pageSize)&page=\(page)" + Self.bound(since))
            return payload.drives
        }
    }

    private static let pageSize = 500

    // teslamateapi serves newest first. from v1.24 it also bounds the list with
    // startDate; older servers ignore the parameter and send the same pages as ever,
    // so the bound is applied here too and paging stops where a page reaches past it.
    // drives can fail on old rows holding nulls (scan error) — broken pages are skipped
    private func pages<T>(since: Date?, start: KeyPath<T, Date>,
                          fetch: (Int) async throws -> [T]) async throws -> [T] {
        var all: [T] = []
        var lastError: Error?
        var failures = 0
        var page = 1
        while page <= 40 {
            do {
                let batch = try await fetch(page)
                all += batch
                failures = 0
                if batch.count < Self.pageSize { break }
                if let since, let oldest = batch.last?[keyPath: start], oldest < since { break }
            } catch {
                lastError = error
                failures += 1
                if failures >= 3 { break }
            }
            page += 1
        }
        if all.isEmpty, let lastError { throw lastError }
        guard let since else { return all }
        return all.filter { $0[keyPath: start] >= since }
    }

    private static func bound(_ since: Date?) -> String {
        guard let since else { return "" }
        return "&startDate=" + since.formatted(.iso8601)
    }

    func drive(carID: Int, driveID: Int) async throws -> Drive {
        let payload: DrivePayload = try await get("/api/v1/cars/\(carID)/drives/\(driveID)")
        return payload.drive
    }

    // plug-ins that never delivered anything have nothing to show and inflate the
    // charge count. TeslaMate's own dashboards drop them the same way
    func charges(carID: Int, since: Date? = nil) async throws -> [Charge] {
        let all: [Charge] = try await pages(since: since, start: \.startDate) { page in
            let payload: ChargesPayload = try await get("/api/v1/cars/\(carID)/charges?show=\(Self.pageSize)&page=\(page)" + Self.bound(since))
            return payload.charges
        }
        return all.filter { ($0.chargeEnergyAdded ?? 0) > 0 }
    }

    func charge(carID: Int, chargeID: Int) async throws -> Charge {
        let payload: ChargePayload = try await get("/api/v1/cars/\(carID)/charges/\(chargeID)")
        return payload.charge
    }
}
