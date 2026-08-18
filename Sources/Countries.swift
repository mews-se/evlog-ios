import Foundation

struct CountryStat: Identifiable {
    let code: String
    let name: String
    let drives: Int
    let km: Double
    let lastVisit: Date?

    var id: String { code }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func day(_ text: String?) -> Date? {
        text.flatMap { isoDay.date(from: $0) }
    }

    // databasen har namnet på Nominatims språk - appen ska följa sitt eget
    var displayName: String {
        Locale.current.localizedString(forRegionCode: code) ?? name
    }

    // regional indicator symbols: "se" blir 🇸🇪
    var flag: String {
        code.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value).map(String.init)
        }.joined()
    }
}

extension GrafanaClient {
    // länderna bor i addresses.raw (Nominatim), inte i teslamateapi
    func countries(carID: Int) async throws -> [CountryStat] {
        let sql = """
        select
          a.raw->'address'->>'country_code' as code,
          a.country as name,
          count(*)::text as drives,
          round(sum(d.distance)::numeric, 0)::text as km,
          to_char(max(d.start_date), 'YYYY-MM-DD') as last_visit
        from drives d
          join addresses a on a.id = d.end_address_id
        where d.car_id = \(carID)
          and a.country is not null
          and a.raw->'address'->>'country_code' is not null
        group by 1, 2
        order by sum(d.distance) desc
        """
        let columns = try await textColumns(sql)
        guard columns.count >= 5 else { return [] }
        let rows = columns.map(\.count).min() ?? 0
        return (0..<rows).compactMap { i in
            guard let code = columns[0][i], let name = columns[1][i] else { return nil }
            return CountryStat(
                code: code,
                name: name,
                drives: Int(columns[2][i] ?? "") ?? 0,
                km: Double(columns[3][i] ?? "") ?? 0,
                lastVisit: CountryStat.day(columns[4][i])
            )
        }
    }
}
