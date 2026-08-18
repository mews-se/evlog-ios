import Foundation
import MapKit

struct Supercharger: Identifiable, Codable {
    let id: Int
    let name: String
    let lat: Double
    let lon: Double

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

// Teslas egen platslista svarar 403 utåt. supercharge.info är en öppen
// community-databas som svarar på ~1,5 s mot Overpass 8-26, och bär status så
// att planerade och stängda platser kan sorteras bort.
struct SuperchargeClient {
    static let attribution = "Data from supercharge.info"

    func sites(around center: CLLocationCoordinate2D, radiusKm: Double) async throws -> [Supercharger] {
        guard let url = URL(string: "https://supercharge.info/service/supercharge/allSites") else {
            throw APIError.badURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }

        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return try JSONDecoder().decode([Site].self, from: data)
            .filter { $0.status == "OPEN" }
            .compactMap { site in
                guard let gps = site.gps else { return nil }
                let distance = CLLocation(latitude: gps.latitude, longitude: gps.longitude).distance(from: origin)
                guard distance <= radiusKm * 1000 else { return nil }
                return Supercharger(
                    id: site.id,
                    name: site.name,
                    lat: gps.latitude,
                    lon: gps.longitude
                )
            }
    }

    // bara fälten kartan faktiskt använder - resten av svaret hoppas över
    private struct Site: Decodable {
        let id: Int
        let name: String
        let status: String?
        let gps: GPS?

        struct GPS: Decodable {
            let latitude: Double
            let longitude: Double
        }
    }
}
