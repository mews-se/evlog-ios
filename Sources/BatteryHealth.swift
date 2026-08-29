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

extension GrafanaClient {
    // every finished charge leaves a reading: the rated range at its last sample, scaled to
    // a full battery. "when new" is the 98th percentile of all readings, "now" the average of
    // the twenty most recent, and capacity is range times the car's kWh-per-rated-km constant
    // (with a median over well-formed charges as the fallback when the constant is missing)
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
          select distinct on (s.charging_process_id)
                 p.end_date, s.rated_battery_range_km * 100.0 / s.usable_battery_level as full_range_km
          from charges s
          join charging_processes p on p.id = s.charging_process_id
          where p.car_id = \(carID) and p.end_date is not null and p.charge_energy_added > 2
            and s.usable_battery_level > 0
          order by s.charging_process_id, s.date desc
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
}
