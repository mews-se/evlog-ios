import Foundation

// the app's stand-in server: three weeks of a made-up Model 3 living in Fremont,
// bundled in teslamateapi's shapes. active on a first launch with no server
// configured, and afterwards only through the switch in Settings - a server that
// stops answering shows its error, never this
enum Demo {
    static var isActive: Bool {
        let defaults = UserDefaults.standard
        let server = (defaults.string(forKey: Pref.server.key) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return defaults.bool(forKey: Pref.demoMode.key) || server.isEmpty
    }

    // the dataset is written against this day, with the story's wall-clock times
    // stored as UTC. the shift moves the newest day to today and cancels the
    // viewer's zone, so the morning commute reads as morning anywhere
    private static let dayZero = "2026-08-28"

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static var shiftSeconds: TimeInterval {
        guard let zero = formatter.date(from: dayZero + "T00:00:00Z") else { return 0 }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: zero),
                                           to: calendar.startOfDay(for: Date())).day ?? 0
        return TimeInterval(days * 86400 - TimeZone.current.secondsFromGMT())
    }

    static func payload(for path: String) throws -> Data {
        guard let name = file(for: path),
              let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            throw APIError.http(404)
        }
        return Data(shifted(raw).utf8)
    }

    // /api/v1/cars -> demo-cars, .../cars/1/drives -> demo-drives,
    // .../drives/12 -> demo-drives-12; queries carry no meaning here
    private static func file(for path: String) -> String? {
        let parts = path.components(separatedBy: "?")[0]
            .components(separatedBy: "/").filter { !$0.isEmpty }
        guard parts.count >= 3, parts[2] == "cars" else { return nil }
        if parts.count == 3 { return "demo-cars" }
        guard parts.count >= 5 else { return nil }
        return parts.count == 5 ? "demo-\(parts[4])" : "demo-\(parts[4])-\(parts[5])"
    }

    private static func shifted(_ json: String) -> String {
        let offset = shiftSeconds
        guard offset != 0 else { return json }
        var out = json
        for range in json.ranges(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/).reversed() {
            if let date = formatter.date(from: String(json[range])) {
                out.replaceSubrange(range, with: formatter.string(from: date.addingTimeInterval(offset)))
            }
        }
        return out
    }

    // MARK: - what Grafana would have answered

    static let marketingName = "LR AWD"
    static let detourFactor = 1.3
    static let heaterDrives: Set<Int> = [1, 24]
    static let heaterCharges: Set<Int> = [2]
    static let coldChargeStarts: Set<Int> = [2]

    static let batteryHealth = BatteryHealth(maxRange: 499, currentRange: 479,
                                             kwhPerKm: 0.156)

    static var countries: [CountryStat] {
        [CountryStat(code: "us", name: "United States", drives: 33, km: 947,
                     lastVisit: Date())]
    }

    // the positions sit at five minute steps, so the figure is as rough as the real one
    static func climateMinutes(from: Date, to: Date) -> Double? {
        let minutes = to.timeIntervalSince(from) / 60
        return minutes < 60 ? (minutes * 0.8).rounded() : nil
    }

    private struct DemoPoint: Decodable {
        let date: Date
        let lat: Double
        let lon: Double
    }

    static func trackPoints() -> [TrackPoint] {
        guard let url = Bundle.main.url(forResource: "demo-positions", withExtension: "json"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let points = (try? decoder.decode([DemoPoint].self, from: Data(shifted(raw).utf8))) ?? []
        return points.map { TrackPoint(date: $0.date, lat: $0.lat, lon: $0.lon) }
    }
}
