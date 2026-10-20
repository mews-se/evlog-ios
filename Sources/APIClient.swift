import Foundation

enum APIError: LocalizedError {
    case noServer
    case noGrafana
    case badURL
    case unreachable
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .noServer: return String(localized: "No server yet. Add your TeslaMate API address under Settings.")
        case .noGrafana: return String(localized: "No Grafana address yet. Add it under Settings to see this.")
        case .badURL: return String(localized: "Invalid server URL. Check the settings.")
        case .unreachable: return String(localized: "The server can't be reached from here. Connect to its network or your VPN, then try again.")
        case .http(let code): return String(localized: "The server returned an error (HTTP \(code)).")
        }
    }
}

// a mistyped LAN address should fail in seconds, not sit on the system's full sixty
enum Net {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()
}

// away from the network the server lives on, every request waits out its timeout
// on its own. one quick look per server answers for all of them, until the app
// leaves the foreground or someone asks again
@MainActor
final class ServerCheck {
    static let shared = ServerCheck()
    private var answers: [String: Task<Bool, Never>] = [:]

    func reachable(_ root: String) async -> Bool {
        if let answer = answers[root] { return await answer.value }
        let answer = Task { await Self.ping(root) }
        answers[root] = answer
        return await answer.value
    }

    func forget() {
        answers = [:]
    }

    // any answer at all means the server is there - Grafana has no /api/ping and says 404
    private nonisolated static func ping(_ root: String) async -> Bool {
        guard let url = URL(string: root + "/api/ping") else { return true }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            _ = try await Net.session.data(for: request)
            return true
        } catch {
            return false
        }
    }
}

struct APIClient {
    let baseURL: String
    var demo: Bool = Demo.isActive

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func get<T: Decodable>(_ path: String) async throws -> T {
        if demo {
            return try Self.decoder.decode(Envelope<T>.self, from: Demo.payload(for: path)).data
        }
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        if root.isEmpty { throw APIError.noServer }
        guard let url = URL(string: root + path) else { throw APIError.badURL }
        guard await ServerCheck.shared.reachable(root) else { throw APIError.unreachable }
        let (data, response) = try await Net.session.data(from: url)
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
        return payload.status.metric(payload.units)
    }

    func updates(carID: Int) async throws -> [SoftwareUpdate] {
        let payload: UpdatesPayload = try await get("/api/v1/cars/\(carID)/updates")
        return payload.updates
    }

    // everything since a date, or everything there is when no date is given
    func drives(carID: Int, since: Date? = nil) async throws -> [Drive] {
        try await pages(since: since, start: \.startDate) { page in
            let payload: DrivesPayload = try await get("/api/v1/cars/\(carID)/drives?show=\(Self.pageSize)&page=\(page)" + Self.bound(since))
            return payload.drives.map { $0.metric(payload.units) }
        }
    }

    private static let pageSize = 500

    // teslamateapi serves newest first. from v1.24 it also bounds the list with
    // startDate; older servers ignore the parameter and send the same pages as ever,
    // so the bound is applied here too and paging stops where a page reaches past it.
    // drives can fail on old rows holding nulls (scan error) — broken pages are skipped,
    // but a server that stops answering is not a run of broken pages
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
                if failures >= 3 || error is URLError { break }
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
        return payload.drive.metric(payload.units)
    }

    // plug-ins that never delivered anything have nothing to show and inflate the
    // charge count. TeslaMate's own dashboards drop them the same way
    func charges(carID: Int, since: Date? = nil) async throws -> [Charge] {
        let all: [Charge] = try await pages(since: since, start: \.startDate) { page in
            let payload: ChargesPayload = try await get("/api/v1/cars/\(carID)/charges?show=\(Self.pageSize)&page=\(page)" + Self.bound(since))
            return payload.charges.map { $0.metric(payload.units) }
        }
        return all.filter { ($0.chargeEnergyAdded ?? 0) > 0 }
    }

    func charge(carID: Int, chargeID: Int) async throws -> Charge {
        let payload: ChargePayload = try await get("/api/v1/cars/\(carID)/charges/\(chargeID)")
        return payload.charge.metric(payload.units)
    }
}
