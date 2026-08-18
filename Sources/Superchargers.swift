import Foundation
import MapKit

struct Supercharger: Identifiable {
    let id: Int
    let name: String
    let coordinate: CLLocationCoordinate2D
    let stalls: Int?
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
                coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon),
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
