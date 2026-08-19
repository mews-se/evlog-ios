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

    // the database holds the name in Nominatim's language - the app follows its own
    var displayName: String {
        Locale.app.localizedString(forRegionCode: code) ?? name
    }

    // regional indicator symbols: "se" becomes 🇸🇪
    var flag: String {
        code.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value).map(String.init)
        }.joined()
    }
}

extension GrafanaClient {
    // road kilometres spent per kilometre as the crow flies, the median across own drives
    func detourFactor(carID: Int) async throws -> Double? {
        let sql = """
        select round(percentile_cont(0.5) within group (order by ratio)::numeric, 2)::text
        from (
          select d.distance / nullif(
              6371 * acos(least(1, greatest(-1,
                sin(radians(ps.latitude)) * sin(radians(pe.latitude)) +
                cos(radians(ps.latitude)) * cos(radians(pe.latitude)) *
                cos(radians(pe.longitude - ps.longitude))))), 0) as ratio
          from drives d
            join positions ps on ps.id = d.start_position_id
            join positions pe on pe.id = d.end_position_id
          where d.car_id = \(carID) and d.distance > 5
        ) t where ratio between 1 and 5
        """
        return try await scalarText(sql).flatMap(Double.init)
    }

    // the drive list carries no climate data, so the heater drives are fetched in one go
    func heaterDrives(carID: Int) async throws -> Set<Int> {
        let sql = """
        select distinct drive_id::text from positions
        where car_id = \(carID) and battery_heater and drive_id is not null
        """
        let columns = try await textColumns(sql)
        guard let ids = columns.first else { return [] }
        return Set(ids.compactMap { $0.flatMap(Int.init) })
    }

    // the countries live in addresses.raw (Nominatim), not in teslamateapi
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
