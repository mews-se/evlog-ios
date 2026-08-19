import Foundation

struct TrackPoint {
    let date: Date
    let lat: Double
    let lon: Double
}

// the positions table is not reachable through teslamateapi — Grafana's datasource API (anonymous viewer) fills the gap
struct GrafanaClient {
    let baseURL: String

    private var root: String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
    }

    private func endpoint(_ path: String) throws -> URL {
        if root.isEmpty { throw APIError.noGrafana }
        guard let url = URL(string: root + path) else { throw APIError.badURL }
        return url
    }

    func positions(carID: Int, condition: String, sampleSeconds: Int) async throws -> [TrackPoint] {
        let uid = try await datasourceUID()
        let sql = """
        select extract(epoch from date) as t, latitude, longitude from positions \
        where car_id = \(carID) and \(condition) \
        and mod(floor(extract(epoch from date))::bigint, \(sampleSeconds)) = 0 order by date
        """

        let url = try endpoint("/api/ds/query")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "queries": [["refId": "A", "datasource": ["uid": uid], "rawSql": sql, "format": "table"]],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(DSResponse.self, from: data)
        guard let values = decoded.results["A"]?.frames.first?.data.values, values.count >= 3 else { return [] }

        let count = values.map(\.count).min() ?? 0
        var points: [TrackPoint] = []
        points.reserveCapacity(count)
        for i in 0..<count {
            guard let t = values[0][i], let lat = values[1][i], let lon = values[2][i] else { continue }
            points.append(TrackPoint(date: Date(timeIntervalSince1970: t), lat: lat, lon: lon))
        }
        return points
    }

    // marketing_name is only in the database, not in teslamateapi
    func marketingName(carID: Int) async throws -> String? {
        try await scalarText("select marketing_name from cars where id = \(carID)")
    }

    // column-wise text answer - callers cast to text in the SQL
    func textColumns(_ sql: String) async throws -> [[String?]] {
        let uid = try await datasourceUID()
        let url = try endpoint("/api/ds/query")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "queries": [["refId": "A", "datasource": ["uid": uid], "rawSql": sql, "format": "table"]],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(DSTextResponse.self, from: data)
        return decoded.results["A"]?.frames.first?.data.values ?? []
    }

    func scalarText(_ sql: String) async throws -> String? {
        let uid = try await datasourceUID()
        let url = try endpoint("/api/ds/query")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "queries": [["refId": "A", "datasource": ["uid": uid], "rawSql": sql, "format": "table"]],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(DSTextResponse.self, from: data)
        let value = decoded.results["A"]?.frames.first?.data.values.first?.first ?? nil
        return value?.isEmpty == false ? value : nil
    }

    private func datasourceUID() async throws -> String {
        let url = try endpoint("/api/datasources")
        let (data, _) = try await URLSession.shared.data(from: url)
        let sources = try JSONDecoder().decode([Datasource].self, from: data)
        guard let uid = sources.first(where: { $0.type.contains("postgres") })?.uid else {
            throw APIError.http(404)
        }
        return uid
    }
}

private struct Datasource: Decodable {
    let uid: String
    let type: String
}

private struct DSTextResponse: Decodable {
    let results: [String: DSTextResult]
}

private struct DSTextResult: Decodable {
    let frames: [DSTextFrame]
}

private struct DSTextFrame: Decodable {
    let data: DSTextData
}

private struct DSTextData: Decodable {
    let values: [[String?]]
}

private struct DSResponse: Decodable {
    let results: [String: DSResult]
}

private struct DSResult: Decodable {
    let frames: [DSFrame]
}

private struct DSFrame: Decodable {
    let data: DSData
}

private struct DSData: Decodable {
    let values: [[Double?]]
}
