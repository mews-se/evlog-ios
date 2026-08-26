import SwiftUI

// the sheet behind the car's name. labels and values are the car's own terms,
// so everything but the chrome stays english on purpose - like the disclaimer
struct CarSpecView: View {
    let api: APIClient
    let carID: Int
    let status: CarStatus?
    let marketingName: String?
    let token: String

    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case full(TessieVehicleConfig, TessieVehicleState)
        case short(tessieFailed: Bool)
    }

    @State private var phase: Phase = .loading
    // /status carries neither vin nor efficiency - /cars fills them in either mode,
    // and brings teslamate's own exterior copy and lifetime counters
    @State private var car: Car?

    var body: some View {
        NavigationStack {
            List {
                identitySection
                switch phase {
                case .loading:
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                case let .full(config, state):
                    specSection("Drivetrain", [
                        ("Front motor", pretty(config.frontDriveUnit)),
                        ("Rear motor", pretty(config.rearDriveUnit)),
                        ("Performance package", pretty(config.performancePackage)),
                        ("Ludicrous mode", yesNo(config.hasLudicrousMode)),
                        ("Air suspension", yesNo(config.hasAirSuspension)),
                    ])
                    specSection("Exterior", [
                        ("Color", pretty(config.exteriorColor)),
                        ("Trim", pretty(config.exteriorTrim)),
                        ("Roof", pretty(config.roofColor)),
                        ("Wheels", pretty(config.wheelType)),
                        ("Spoiler", pretty(config.spoilerType)),
                        ("Headlamps", pretty(config.headlampType)),
                    ])
                    specSection("Interior", [
                        // the digit in Black2/White2 is tesla's generation suffix, not a shade
                        ("Trim", pretty(config.interiorTrimType.map {
                            $0.replacingOccurrences(of: #"\d+"#, with: "", options: .regularExpression)
                        })),
                        ("Rear seat heaters", yesNo(config.rearSeatHeaters.map { $0 > 0 })),
                        ("Seat cooling", yesNo(config.hasSeatCooling)),
                        ("Third row seats", config.thirdRowSeats.flatMap { $0 == "None" ? nil : pretty($0) }),
                    ])
                    specSection("Charging", [
                        ("Charge port", config.chargePortType?.uppercased()),
                        ("Motorized charge port", yesNo(config.motorizedChargePort)),
                    ])
                    specSection("Assistance", [
                        ("Driver assist", pretty(config.driverAssist)),
                        ("Efficiency package", pretty(config.efficiencyPackage)),
                    ], footer: Text("From the car, via Tessie."))
                    specSection("Lifetime", lifetimeRows + [
                        ("Energy used", state.chargeState?.lifetimeEnergyUsed.map {
                            $0.formatted(.number.precision(.fractionLength(0))) + " kWh"
                        }),
                    ])
                case let .short(tessieFailed):
                    specSection("Exterior", [
                        ("Color", pretty(car?.carExterior?.exteriorColor)),
                        ("Wheels", pretty(car?.carExterior?.wheelType)),
                        ("Spoiler", pretty(car?.carExterior?.spoilerType)),
                    ])
                    specSection("Lifetime", lifetimeRows)
                    Section {
                    } footer: {
                        if tessieFailed {
                            Text("Tessie didn't answer, so this is what TeslaMate knows.")
                        } else {
                            Text("Add a Tessie API key in Settings and the car itself fills in the rest.")
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: status?.displayName ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    // what teslamate knows on its own - the sheet leads with it either way
    private var identitySection: some View {
        specSection(nil, [
            ("Model", (status?.carDetails?.model ?? car?.carDetails?.model).map { model in
                "Model \(model)" + (marketingName.map { " \($0)" } ?? "")
            }),
            ("Trim", (status?.carDetails?.trimBadging ?? car?.carDetails?.trimBadging)?.uppercased()),
            ("VIN", status?.carDetails?.vin ?? car?.carDetails?.vin),
            ("Efficiency", (status?.carDetails?.efficiency ?? car?.carDetails?.efficiency).map {
                Fmt.consumption($0 * 1000)
            }),
        ])
    }

    // teslamate's side of the lifetime story - the car's energy counter joins when tessie answers
    private var lifetimeRows: [(String, String?)] {
        [
            ("Logged since", car?.teslamateDetails?.insertedAt
                .flatMap { CountryStat.day(String($0.prefix(10))) }.map { Fmt.date($0) }),
            ("Drives", car?.teslamateStats?.totalDrives.map { $0.formatted() }),
            ("Charges", car?.teslamateStats?.totalCharges.map { $0.formatted() }),
            ("Software updates", car?.teslamateStats?.totalUpdates.map { $0.formatted() }),
        ]
    }

    @ViewBuilder
    private func specSection(_ title: String?, _ rows: [(String, String?)], footer: Text? = nil) -> some View {
        let present = rows.compactMap { row in row.1.map { (row.0, $0) } }
        if !present.isEmpty {
            Section {
                ForEach(present, id: \.0) { row in
                    LabeledContent(row.0) {
                        Text(verbatim: row.1)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                if let title { Text(verbatim: title) }
            } footer: {
                if let footer { footer }
            }
        }
    }

    private func load() async {
        car = (try? await api.cars())?.first { $0.carId == carID }
        guard !token.isEmpty else {
            phase = .short(tessieFailed: false)
            return
        }
        let vin = status?.carDetails?.vin ?? car?.carDetails?.vin
        let vehicle = try? await TessieClient(token: token).vehicle(vin: vin)
        if let state = vehicle?.lastState, let config = state.vehicleConfig {
            phase = .full(config, state)
        } else {
            phase = .short(tessieFailed: true)
        }
    }

    private func yesNo(_ value: Bool?) -> String? {
        value.map { $0 ? "Yes" : "No" }
    }

    // "DeepBlue" reads as "Deep Blue", "Pinwheel18CapKit" as "Pinwheel 18 Cap Kit";
    // capital runs like MOSFET are left alone
    private func pretty(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
            .replacingOccurrences(of: #"(?<=[a-z])(?=[A-Z])"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=[A-Za-z])(?=\d)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d)(?=[A-Za-z])"#, with: " ", options: .regularExpression)
    }
}
