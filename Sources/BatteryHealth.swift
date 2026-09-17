import Foundation

// deliberately not the dashboard's query — TeslaMate is AGPL-licensed, this app is MIT
struct BatteryHealth {
    let maxRange: Double
    let currentRange: Double
    let kwhPerKm: Double

    var maxCapacity: Double { maxRange * kwhPerKm }
    var currentCapacity: Double { currentRange * kwhPerKm }

    var degradation: Double? {
        guard maxRange > 0 else { return nil }
        return max(0, 100 - currentRange * 100 / maxRange)
    }

    var health: Double? {
        degradation.map { min(100, 100 - $0) }
    }

    var lostRange: Double { max(0, maxRange - currentRange) }
}

// one finished charge, one reading: where the odometer stood when it began and how far a
// full battery would have reached, by the rated range at its end
struct CapacityReading: Identifiable {
    let id: Int
    let odometerKm: Double
    let fullRangeKm: Double
}

// how long the battery has stood at one charge level, over the whole logging history
struct LevelTime: Identifiable {
    let level: Int
    let seconds: Double
    var id: Int { level }
}

extension GrafanaClient {
    // every finished charge leaves a reading: the rated range at its last sample, scaled to
    // a full battery
    private static func readings(carID: Int) -> String {
        """
        select distinct on (s.charging_process_id)
               s.charging_process_id as id, p.end_date, p.position_id,
               s.rated_battery_range_km * 100.0 / s.usable_battery_level as full_range_km
        from charges s
        join charging_processes p on p.id = s.charging_process_id
        where p.car_id = \(carID) and p.end_date is not null and p.charge_energy_added > 2
          and s.usable_battery_level > 0
        order by s.charging_process_id, s.date desc
        """
    }

    // "when new" is the 98th percentile of all readings, "now" the average of the twenty
    // most recent, and capacity is range times the car's kWh-per-rated-km constant (with a
    // median over well-formed charges as the fallback when the constant is missing)
    func batteryHealth(carID: Int) async throws -> BatteryHealth? {
        if demo { return Demo.batteryHealth }
        let sql = """
        with spend as (
          select coalesce(
            (select efficiency from cars where id = \(carID) and efficiency > 0),
            (select percentile_cont(0.5) within group (order by charge_energy_added / (end_rated_range_km - start_rated_range_km))
               from charging_processes
              where car_id = \(carID) and end_rated_range_km > start_rated_range_km + 1
                and charge_energy_added > 2 and duration_min >= 10)
          ) as kwh_per_km
        ),
        readings as (
          \(Self.readings(carID: carID))
        )
        select round((percentile_cont(0.98) within group (order by full_range_km))::numeric, 1)::text as range_new,
               round((select avg(full_range_km)
                        from (select full_range_km from readings order by end_date desc limit 20) recent)::numeric, 1)::text as range_now,
               (select kwh_per_km::text from spend) as kwh_per_km
        from readings
        having count(*) >= 5
        """
        let columns = try await textColumns(sql)
        guard columns.count == 3,
              let maxRange = columns[0].first.flatMap({ $0 }).flatMap(Double.init),
              let currentRange = columns[1].first.flatMap({ $0 }).flatMap(Double.init),
              let kwhPerKm = columns[2].first.flatMap({ $0 }).flatMap(Double.init)
        else { return nil }
        return BatteryHealth(maxRange: maxRange, currentRange: currentRange, kwhPerKm: kwhPerKm)
    }

    // the same readings against the odometer, lowest mileage first, so the health view can
    // draw where the capacity is heading
    func capacityReadings(carID: Int) async throws -> [CapacityReading] {
        if demo { return Demo.capacityReadings }
        let sql = """
        with readings as (
          \(Self.readings(carID: carID))
        )
        select r.id::text, round(o.odometer)::text, round(r.full_range_km::numeric, 1)::text
        from readings r
        join positions o on o.id = r.position_id
        order by o.odometer
        """
        let columns = try await textColumns(sql)
        guard columns.count == 3 else { return [] }
        let count = columns.map(\.count).min() ?? 0
        return (0..<count).compactMap { i in
            guard let id = columns[0][i].flatMap(Int.init),
                  let km = columns[1][i].flatMap(Double.init),
                  let range = columns[2][i].flatMap(Double.init) else { return nil }
            return CapacityReading(id: id, odometerKm: km, fullRangeKm: range)
        }
    }

    // every stored level is held until the next reading, so a night asleep counts for the
    // level the car slept at. driving positions come every couple of seconds and are
    // thinned to one a minute, which makes the query quick without moving the shares
    func levelTimes(carID: Int) async throws -> [LevelTime] {
        if demo { return Demo.levelTimes }
        let sql = """
        with samples as (
          select date, battery_level from positions
          where car_id = \(carID) and battery_level is not null
            and (drive_id is null or mod(floor(extract(epoch from date))::bigint, 60) = 0)
          union all
          select c.date, c.battery_level from charges c
          join charging_processes p on p.id = c.charging_process_id
          where p.car_id = \(carID) and c.battery_level is not null
        ),
        held as (
          select battery_level, extract(epoch from lead(date) over (order by date) - date) as seconds
          from samples
        )
        select battery_level::text, round(sum(seconds))::text
        from held where seconds is not null
        group by battery_level order by battery_level
        """
        let columns = try await textColumns(sql)
        guard columns.count == 2 else { return [] }
        let count = columns.map(\.count).min() ?? 0
        return (0..<count).compactMap { i in
            guard let level = columns[0][i].flatMap(Int.init),
                  let seconds = columns[1][i].flatMap(Double.init) else { return nil }
            return LevelTime(level: level, seconds: seconds)
        }
    }
}
