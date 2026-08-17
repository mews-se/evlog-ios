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
    let driveDetails: [DrivePoint]?

    var id: Int { driveId }
    var distance: Double { odometerDetails?.odometerDistance ?? 0 }
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

    var id: Int { detailId }
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

    // added/tid, samma semantik som Grafanas Ø Power-kolumn
    var avgPowerKw: Double? {
        guard let minutes = durationMin, minutes > 0,
              let energy = chargeEnergyAdded ?? chargeEnergyUsed else { return nil }
        return energy / (minutes / 60)
    }

    // teslamateapi serialiserar null-kostnad som 0 — 0 betyder alltså "ej registrerad", inte gratis
    var displayCost: Double? {
        guard let cost, cost > 0 else { return nil }
        return cost
    }

    // listan saknar effektdata — snitt över 20 kW kan bara vara DC (AC toppar 11 kW ombord)
    var isDC: Bool {
        if let points = chargeDetails {
            return points.contains { $0.fastChargerInfo?.fastChargerPresent == true }
        }
        return (avgPowerKw ?? 0) > 20
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
