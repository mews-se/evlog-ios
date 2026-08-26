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
    let carExterior: CarExterior?
    let teslamateDetails: TeslaMateDetails?
    let teslamateStats: TeslaMateStats?

    var id: Int { carId }
}

struct CarExterior: Decodable {
    let exteriorColor: String?
    let spoilerType: String?
    let wheelType: String?
}

struct TeslaMateDetails: Decodable {
    let insertedAt: String?
}

struct TeslaMateStats: Decodable {
    let totalCharges: Int?
    let totalDrives: Int?
    let totalUpdates: Int?
}

struct CarDetails: Decodable {
    let model: String?
    let trimBadging: String?
    let vin: String?
    let efficiency: Double?
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

// teslamateapi writes null rather than an empty list when nothing matched
struct DrivesPayload: Decodable {
    private let list: [Drive]?
    var drives: [Drive] { list ?? [] }

    enum CodingKeys: String, CodingKey { case list = "drives" }
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
    let startRange: Double?
    let endRange: Double?
    let rangeDiff: Double?
}

struct OdometerDetails: Decodable {
    let odometerStart: Double?
    let odometerEnd: Double?
    let odometerDistance: Double?
}

// charges carry no usable levels, so those decode nil there
struct DriveBattery: Decodable {
    let startBatteryLevel: Int?
    let startUsableBatteryLevel: Int?
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
    private let list: [Charge]?
    var charges: [Charge] { list ?? [] }

    enum CodingKeys: String, CodingKey { case list = "charges" }
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
    let rangeRated: RangeDetails?
    let outsideTempAvg: Double?
    let odometer: Double?
    let latitude: Double?
    let longitude: Double?
    let chargeDetails: [ChargePoint]?

    var id: Int { chargeId }

    // what the charger delivered over the time it ran, the same side of the on-board
    // charger as the max, so a steady 11 kW AC charge reads 11 and not the 10 that
    // reached the battery. TeslaMate's own column divides the added energy instead
    var avgPowerKw: Double? {
        guard let minutes = durationMin, minutes > 0,
              let energy = chargeEnergyUsed ?? chargeEnergyAdded else { return nil }
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
    // the car's own running total for the session, not TeslaMate's per-process figure:
    // it only goes back to zero when the cable comes out
    let chargeEnergyAdded: Double?
    let chargerDetails: ChargerDetails?
    let fastChargerInfo: FastChargerInfo?

    var id: Int { detailId }
}

// a car left plugged in does not charge once: standby runs off the cable, the level
// dips, charging resumes, and TeslaMate records a process for every top-up. joined
// back together the stretch gets numbers that mean something
struct ChargeGroup: Identifiable {
    let parts: [Charge]

    var id: Int { parts[0].chargeId }
    var first: Charge { parts[0] }
    var last: Charge { parts[parts.count - 1] }

    var startDate: Date { first.startDate }
    var endDate: Date? { last.endDate }
    var address: String? { first.address }
    var isDC: Bool { parts.contains { $0.isDC } }

    var batteryDetails: DriveBattery? {
        DriveBattery(startBatteryLevel: first.batteryDetails?.startBatteryLevel,
                     startUsableBatteryLevel: first.batteryDetails?.startUsableBatteryLevel,
                     endBatteryLevel: last.batteryDetails?.endBatteryLevel)
    }

    var energyAdded: Double? {
        let values = parts.compactMap(\.chargeEnergyAdded)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var energyUsed: Double? {
        let values = parts.compactMap(\.chargeEnergyUsed)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var efficiency: Double? {
        guard let added = energyAdded, let used = energyUsed, added > 0, used > 0 else { return nil }
        return added / used
    }

    // active charging only - the gaps in between are standby, not charging
    var chargeMinutes: Double? {
        let values = parts.compactMap(\.durationMin)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var pluggedMinutes: Double? {
        guard let endDate else { return nil }
        return endDate.timeIntervalSince(startDate) / 60
    }

    var maxPowerKw: Double? { parts.compactMap(\.maxPowerKw).max() }

    var avgPowerKw: Double? {
        guard let minutes = chargeMinutes, minutes > 0, let energy = energyUsed ?? energyAdded else { return nil }
        return energy / (minutes / 60)
    }

    var outsideTempAvg: Double? {
        let values = parts.compactMap { part -> (temp: Double, weight: Double)? in
            guard let temp = part.outsideTempAvg else { return nil }
            return (temp, part.durationMin ?? 1)
        }
        let weight = values.reduce(0) { $0 + $1.weight }
        guard weight > 0 else { return nil }
        return values.reduce(0) { $0 + $1.temp * $1.weight } / weight
    }

    func cost(tessieCosts: [Int: Double]) -> Double? {
        let values = parts.compactMap { $0.displayCost ?? tessieCosts[$0.chargeId] }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    func usesTessieCost(_ tessieCosts: [Int: Double]) -> Bool {
        parts.contains { $0.displayCost == nil && tessieCosts[$0.chargeId] != nil }
    }

    // the join rule: same place, no drive in between, and a level that held still.
    // an unplugged car drifts, a plugged one does not, so the level is the plug signal
    // and no time cap is needed
    static func stitch(_ charges: [Charge], drives: [Drive]) -> [ChargeGroup] {
        let sorted = charges.sorted { $0.startDate < $1.startDate }
        let driveStarts = drives.map(\.startDate)
        var groups: [ChargeGroup] = []
        var current: [Charge] = []
        for charge in sorted {
            if let previous = current.last, joins(previous, charge, driveStarts: driveStarts) {
                current.append(charge)
            } else {
                if !current.isEmpty { groups.append(ChargeGroup(parts: current)) }
                current = [charge]
            }
        }
        if !current.isEmpty { groups.append(ChargeGroup(parts: current)) }
        return groups
    }

    private static func joins(_ previous: Charge, _ next: Charge, driveStarts: [Date]) -> Bool {
        guard let end = previous.endDate,
              let place = previous.address, place == next.address,
              let from = previous.batteryDetails?.endBatteryLevel,
              let to = next.batteryDetails?.startBatteryLevel,
              from - to <= 1
        else { return false }
        return !driveStarts.contains { $0 >= end && $0 <= next.startDate }
    }
}

struct FastChargerInfo: Decodable {
    let fastChargerPresent: Bool?
}

struct ChargerDetails: Decodable {
    let chargerPower: Double?
}
