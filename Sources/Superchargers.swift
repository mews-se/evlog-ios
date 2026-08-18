import Foundation
import MapKit

struct Supercharger: Identifiable, Codable {
    let id: Int
    let name: String
    let lat: Double
    let lon: Double
    let stalls: Int?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

// laddare flyttar sig sällan, så svaret sparas en vecka och visas direkt vid
// nästa öppning medan en färsk fråga får ta sin tid i bakgrunden
enum ChargerCache {
    private static let maxAge: TimeInterval = 7 * 24 * 3600

    private struct Entry: Codable {
        let saved: Date
        let chargers: [Supercharger]
    }

    // grov nyckel: rör man sig några kilometer duger samma lista
    static func key(_ center: CLLocationCoordinate2D, _ radiusKm: Double) -> String {
        String(format: "%.1f_%.1f_%.0f", center.latitude, center.longitude, (radiusKm / 25).rounded() * 25)
    }

    private static func url(_ key: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("chargers-\(key).json")
    }

    static func load(_ key: String) -> (chargers: [Supercharger], stale: Bool)? {
        guard let url = url(key), let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        return (entry.chargers, Date().timeIntervalSince(entry.saved) > maxAge)
    }

    static func save(_ chargers: [Supercharger], _ key: String) {
        guard let url = url(key),
              let data = try? JSONEncoder().encode(Entry(saved: Date(), chargers: chargers)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// Teslas egen platslista svarar 403 utåt, så laddarna hämtas ur OpenStreetMap
// via Overpass. Fri tjänst utan nyckel - därav en enda fråga per kartöppning.
struct OverpassClient {
    static let attribution = "© OpenStreetMap contributors"

    func superchargers(around center: CLLocationCoordinate2D, radiusKm: Double) async throws -> [Supercharger] {
        // cirkelfråga i stället för bounding box: hämtar bara det som ligger inom räckvidden
        let query = """
        [out:json][timeout:45];node(around:\(Int(radiusKm * 1000)),\(center.latitude),\(center.longitude))        ["amenity"="charging_station"]["operator"~"Tesla",i];out body;
        """

        guard let url = URL(string: "https://overpass-api.de/api/interpreter") else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Overpass svarar 406 på anrop utan egen User-Agent
        request.setValue("Mate (TeslaMate client)", forHTTPHeaderField: "User-Agent")
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
        return try JSONDecoder().decode(OverpassResponse.self, from: data).elements.map {
            Supercharger(
                id: $0.id,
                name: $0.tags?.name ?? String(localized: "Supercharger"),
                lat: $0.lat,
                lon: $0.lon,
                stalls: $0.tags?.capacity.flatMap(Int.init)
            )
        }
    }
}

private struct OverpassResponse: Decodable {
    let elements: [Element]

    struct Element: Decodable {
        let id: Int
        let lat: Double
        let lon: Double
        let tags: Tags?
    }

    struct Tags: Decodable {
        let name: String?
        let capacity: String?
    }
}
