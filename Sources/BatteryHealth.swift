import Foundation

// Batterihälsan räknas ut i databasen med TeslaMates egen formel (aux-variabeln i
// battery-health.json). Egen approximation skulle ge andra siffror än dashboarden.
struct BatteryHealth: Decodable {
    let maxRange: Double
    let currentRange: Double
    let maxCapacity: Double
    let currentCapacity: Double
    let ratedEfficiency: Double

    enum CodingKeys: String, CodingKey {
        case maxRange = "MaxRange"
        case currentRange = "CurrentRange"
        case maxCapacity = "MaxCapacity"
        case currentCapacity = "CurrentCapacity"
        case ratedEfficiency = "RatedEfficiency"
    }

    var degradation: Double? {
        guard maxCapacity > 0, currentCapacity > 1 else { return nil }
        return max(0, 100 - currentCapacity * 100 / maxCapacity)
    }

    var health: Double? {
        degradation.map { min(100, 100 - $0) }
    }

    var lostRange: Double { max(0, maxRange - currentRange) }
}

extension GrafanaClient {
    func batteryHealth(carID: Int) async throws -> BatteryHealth? {
        let sql = #"""
WITH Aux as (
    SELECT 
        car_id,
        COALESCE(derived_efficiency, car_efficiency) AS efficiency
    FROM (
        SELECT
            ROUND((charge_energy_added / NULLIF(end_rated_range_km - start_rated_range_km, 0))::numeric, 3) * 100 AS derived_efficiency,
            COUNT(*) as count,
            cars.id as car_id,
            cars.efficiency * 100 AS car_efficiency
        FROM cars
            LEFT JOIN charging_processes ON
                cars.id = charging_processes.car_id 
                AND duration_min > 10
                AND end_battery_level <= 95
                AND start_rated_range_km IS NOT NULL
                AND end_rated_range_km IS NOT NULL
                AND charge_energy_added > 0
        WHERE cars.id = \#(carID)
        GROUP BY 1, 3, 4
        ORDER BY 2 DESC
        LIMIT 1
    ) AS Efficiency
),

CurrentCapacity AS (
    SELECT
        AVG(Capacity) AS Capacity
    FROM (
        SELECT 
            c.rated_battery_range_km * aux.efficiency / c.usable_battery_level AS Capacity
        FROM charging_processes cp
            INNER JOIN charges c ON c.charging_process_id = cp.id 
            INNER JOIN aux ON cp.car_id = aux.car_id
        WHERE
            cp.car_id = \#(carID)
            AND cp.end_date IS NOT NULL
            AND cp.charge_energy_added >= aux.efficiency
            AND c.usable_battery_level > 0
        ORDER BY cp.end_date DESC, c.date desc
        LIMIT 100
    ) AS lastCharges
),

MaxCapacity AS (
    SELECT 
        MAX(c.rated_battery_range_km * aux.efficiency / c.usable_battery_level) AS Capacity
    FROM charging_processes cp
        INNER JOIN (
            SELECT
                charging_process_id,
                MAX(date) as date FROM charges WHERE usable_battery_level > 0 GROUP BY charging_process_id
        ) AS gcharges ON
            cp.id = gcharges.charging_process_id
        INNER JOIN charges c ON
            c.charging_process_id = cp.id
            AND c.date = gcharges.date
        INNER JOIN aux ON cp.car_id = aux.car_id
    WHERE
        cp.car_id = \#(carID)
        AND cp.end_date IS NOT NULL
        AND cp.charge_energy_added >= aux.efficiency
),

CurrentRange AS (
    SELECT
        (range * 100.0 / usable_battery_level) AS range
    FROM (
        (
            SELECT
                date,
                rated_battery_range_km AS range,
                usable_battery_level AS usable_battery_level
            FROM positions
            WHERE
                car_id = \#(carID)
                AND ideal_battery_range_km IS NOT NULL
                AND usable_battery_level > 0 
            ORDER BY date DESC
            LIMIT 1
        )
        UNION ALL
        (
            SELECT date,
                rated_battery_range_km AS range,
                usable_battery_level as usable_battery_level
            FROM charges c
                INNER JOIN charging_processes p ON p.id = c.charging_process_id
            WHERE
                p.car_id = \#(carID)
                AND usable_battery_level > 0
            ORDER BY date DESC
            LIMIT 1
        )
    ) AS data
    ORDER BY date DESC
    LIMIT 1
),

MaxRange AS (
    SELECT
        floor(extract(epoch from date)/86400)*86400 AS time,
        CASE
            WHEN sum(usable_battery_level) = 0 THEN sum(rated_battery_range_km) * 100
            ELSE sum(rated_battery_range_km) / sum(usable_battery_level) * 100
        END AS range
    FROM (
        SELECT
            battery_level,
            usable_battery_level,
            date,
            rated_battery_range_km
        FROM charges c 
            INNER JOIN charging_processes p ON p.id = c.charging_process_id 
        WHERE
            p.car_id = \#(carID)
            AND usable_battery_level IS NOT NULL
    ) AS data
    GROUP BY 1
    ORDER BY 2 DESC
    LIMIT 1
),

Base AS (
    SELECT NULL
)

SELECT
    json_build_object(
        'MaxRange', convert_km(MaxRange.range,'km'),
        'CurrentRange', convert_km(CurrentRange.range,'km'),
        'MaxCapacity', MaxCapacity.Capacity,
        'CurrentCapacity', CASE WHEN CurrentCapacity.Capacity IS NULL THEN 1 ELSE CurrentCapacity.Capacity END,
        'RatedEfficiency', aux.efficiency
    ) #>> '{}'
FROM Base
    LEFT JOIN MaxRange ON true
    LEFT JOIN CurrentRange ON true
    LEFT JOIN Aux ON true
    LEFT JOIN MaxCapacity ON true
    LEFT JOIN CurrentCapacity ON true
"""#
        guard let raw = try await scalarText(sql) , let data = raw.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(BatteryHealth.self, from: data)
    }
}
