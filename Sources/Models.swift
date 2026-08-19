import Foundation

struct Envelope<T: Decodable>: Decodable {
    let data: T
}

// MARK: - /cars

struct CarsPayload: Decodable {
    let cars: [Car]
}

struct Car: Decodable, Identifiable {
    let carId: Int
    let name: String
    let carDetails: CarDetails?

    var id: Int { carId }
}

struct CarDetails: Decodable {
    let model: String?
    let trimBadging: String?
    let vin: String?
}

// MARK: - /status

struct StatusPayload: Decodable {
    let status: CarStatus
}

struct CarStatus: Decodable {
    let displayName: String?
    let state: String?
    let stateSince: Date?
    let odometer: Double?
    let carStatus: CarFlags?
    let carDetails: CarDetails?
    let carGeodata: Geodata?
    let carVersions: Versions?
    let drivingDetails: DrivingDetails?
    let climateDetails: ClimateDetails?
    let batteryDetails: BatteryStatus?
    let chargingDetails: ChargingDetails?
}

struct CarFlags: Decodable {
    let healthy: Bool?
    let locked: Bool?
    let sentryMode: Bool?
    let windowsOpen: Bool?
    let doorsOpen: Bool?
    let trunkOpen: Bool?
    let frunkOpen: Bool?
    let isUserPresent: Bool?
}

struct Geodata: Decodable {
    let geofence: String?
    let latitude: Double?
    let longitude: Double?
}

struct Versions: Decodable {
    let version: String?
    let updateAvailable: Bool?
    let updateVersion: String?
}

struct DrivingDetails: Decodable {
    let shiftState: String?
    let power: Double?
    let speed: Double?
}

struct ClimateDetails: Decodable {
    let isClimateOn: Bool?
    let insideTemp: Double?
    let outsideTemp: Double?
    let isPreconditioning: Bool?
}

struct BatteryStatus: Decodable {
    let estBatteryRange: Double?
    let ratedBatteryRange: Double?
    let idealBatteryRange: Double?
    let batteryLevel: Int?
    let usableBatteryLevel: Int?

    // the same expression as TeslaMate's projected range dashboard: scales up to 100 %
    var projectedRatedRange: Double? {
        guard let range = ratedBatteryRange, let level = usableBatteryLevel ?? batteryLevel, level > 0 else { return nil }
        return range / Double(level) * 100
    }
}

struct ChargingDetails: Decodable {
    let pluggedIn: Bool?
    let chargingState: String?
    let chargeEnergyAdded: Double?
    let chargeLimitSoc: Int?
    let chargerPower: Double?
    let timeToFullCharge: Double?
}

// MARK: - /drives

struct DrivesPayload: Decodable {
    let drives: [Drive]
}

struct DrivePayload: Decodable {
    let drive: Drive
}

struct Drive: Decodable, Identifiable {
    let driveId: Int
    let startDate: Date
    let endDate: Date?
    let startAddress: String?
    let endAddress: String?
    let odometerDetails: OdometerDetails?
    let durationMin: Double?
    let speedMax: Double?
    let speedAvg: Double?
    let batteryDetails: DriveBattery?
    let outsideTempAvg: Double?
    let energyConsumedNet: Double?
    let consumptionNet: Double?
    let rangeRated: RangeDetails?
    let driveDetails: [DrivePoint]?

    var id: Int { driveId }
    var distance: Double { odometerDetails?.odometerDistance ?? 0 }

    // streamed position rows carry no climate data, so only a subset holds the flag
    var batteryHeaterUsed: Bool {
        driveDetails?.contains { $0.batteryInfo?.batteryHeater == true } ?? false
    }

    // short rolls are dominated by idle losses - the measure is noise under a kilometre
    var efficiencyPct: Double? {
        guard let diff = rangeRated?.rangeDiff, diff > 0, distance >= 1 else { return nil }
        return distance / diff * 100
    }

    // teslamateapi gates consumption_net on a hidden battery buffer but leaves the energy ungated
    var consumptionWhPerKm: Double? {
        if let consumptionNet { return consumptionNet }
        guard let energyConsumedNet, distance >= 1 else { return nil }
        return energyConsumedNet / distance * 1000
    }

    // Grafana's Energy recovered: negative power integrated over the drive. teslamateapi
    // truncates its timestamps to whole seconds, so the sum lands a few percent off the panel's
    var regenKWh: Double? {
        guard let points = driveDetails, !points.isEmpty else { return nil }
        let regen = points
            .compactMap { p -> (date: Date, power: Double)? in
                guard let date = p.date, let power = p.power, power < 0 else { return nil }
                return (date, power)
            }
            .sorted { $0.date < $1.date }
        var total = 0.0
        for (previous, point) in zip(regen, regen.dropFirst()) {
            let seconds = point.date.timeIntervalSince(previous.date)
            // a gap means regen stopped in between, not that it carried on
            if seconds > 0, seconds < 1.5 { total -= point.power * seconds / 3600 }
        }
        return total
    }
}

struct RangeDetails: Decodable {
    let rangeDiff: Double?
}

struct OdometerDetails: Decodable {
    let odometerDistance: Double?
}

struct DriveBattery: Decodable {
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
}

struct DrivePoint: Decodable, Identifiable {
    let detailId: Int
    let date: Date?
    let latitude: Double?
    let longitude: Double?
    let speed: Double?
    let power: Double?
    let batteryLevel: Int?
    let batteryInfo: PointBattery?

    var id: Int { detailId }
}

struct PointBattery: Decodable {
    // the climate_state flag, not charge_state's battery_heater_on, which this car
    // never reports
    let batteryHeater: Bool?
}

// MARK: - /updates

struct UpdatesPayload: Decodable {
    let updates: [SoftwareUpdate]
}

struct SoftwareUpdate: Decodable, Identifiable {
    let updateId: Int
    let startDate: Date?
    let endDate: Date?
    let version: String?

    var id: Int { updateId }

    // the version string can carry a build hash, which notateslaapp does not want
    var shortVersion: String? {
        guard let first = version?.components(separatedBy: " ").first, !first.isEmpty else { return nil }
        return first
    }

    var releaseNotesURL: URL? {
        guard let shortVersion else { return nil }
        return URL(string: "https://www.notateslaapp.com/software-updates/version/\(shortVersion)/release-notes")
    }
}

// MARK: - /charges

struct ChargesPayload: Decodable {
    let charges: [Charge]
}

struct ChargePayload: Decodable {
    let charge: Charge
}

struct Charge: Decodable, Identifiable {
    let chargeId: Int
    let startDate: Date
    let endDate: Date?
    let address: String?
    let chargeEnergyAdded: Double?
    let chargeEnergyUsed: Double?
    let cost: Double?
    let durationMin: Double?
    let batteryDetails: DriveBattery?
    let outsideTempAvg: Double?
    let odometer: Double?
    let latitude: Double?
    let longitude: Double?
    let chargeDetails: [ChargePoint]?

    var id: Int { chargeId }

    // added/time, the same semantics as Grafana's Ø Power column
    var avgPowerKw: Double? {
        guard let minutes = durationMin, minutes > 0,
              let energy = chargeEnergyAdded ?? chargeEnergyUsed else { return nil }
        return energy / (minutes / 60)
    }

    // teslamateapi serialises a null cost as 0 — so 0 means "not recorded", not free
    var displayCost: Double? {
        guard let cost, cost > 0 else { return nil }
        return cost
    }

    // the list carries no power data — an average above 20 kW can only be DC (AC tops out at 11 kW on board)
    var isDC: Bool {
        if let points = chargeDetails {
            return points.contains { $0.fastChargerInfo?.fastChargerPresent == true }
        }
        return (avgPowerKw ?? 0) > 20
    }

    // added/used - the rest went to cooling, heating and charging losses
    var efficiency: Double? {
        guard let added = chargeEnergyAdded, let used = chargeEnergyUsed, added > 0, used > 0 else { return nil }
        return added / used
    }

    var maxPowerKw: Double? {
        chargeDetails?.compactMap { $0.chargerDetails?.chargerPower }.max()
    }
}

struct ChargePoint: Decodable, Identifiable {
    let detailId: Int
    let date: Date?
    let batteryLevel: Int?
    let chargerDetails: ChargerDetails?
    let fastChargerInfo: FastChargerInfo?

    var id: Int { detailId }
}

struct FastChargerInfo: Decodable {
    let fastChargerPresent: Bool?
}

struct ChargerDetails: Decodable {
    let chargerPower: Double?
}
