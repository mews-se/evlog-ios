import SwiftUI
import MapKit
import Charts

struct ChargesView: View {
    let api: APIClient
    let carID: Int

    @State private var charges: [Charge] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if !charges.isEmpty {
                    List {
                        Section {
                            YearSummaryCard(charges: charges)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        Section {
                            ForEach(charges) { charge in
                                NavigationLink(value: charge.chargeId) {
                                    ChargeRow(charge: charge)
                                }
                            }
                        }
                    }
                    .navigationDestination(for: Int.self) { chargeID in
                        ChargeDetailView(api: api, carID: carID, chargeID: chargeID)
                    }
                } else if let error {
                    ErrorCard(message: error) { Task { await load() } }
                } else if loaded {
                    ContentUnavailableView("No charges yet", systemImage: "bolt.fill")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Charges")
            .refreshable { await load() }
            .task { if !loaded { await load() } }
        }
    }

    private func load() async {
        do {
            charges = try await api.charges(carID: carID, results: 2000)
            error = nil
        } catch {
            if charges.isEmpty { self.error = error.localizedDescription }
        }
        loaded = true
    }
}

struct YearSummaryCard: View {
    let charges: [Charge]

    private var year: [Charge] {
        charges.filter { Calendar.current.isDate($0.startDate, equalTo: .now, toGranularity: .year) }
    }

    private var cost: Double { year.compactMap(\.displayCost).reduce(0, +) }
    private var energy: Double { year.compactMap(\.chargeEnergyAdded).reduce(0, +) }
    private var dcShare: Double {
        guard energy > 0 else { return 0 }
        return year.filter(\.isDC).compactMap(\.chargeEnergyAdded).reduce(0, +) / energy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This year")
                .font(.subheadline.weight(.semibold))
            HStack {
                summaryItem(Fmt.kr(cost), String(localized: "Cost"), .blue)
                summaryItem(Fmt.kwh(energy), String(localized: "Energy"), .green)
                summaryItem("\(year.count)", String(localized: "Charges"), .secondary)
            }
            Text(verbatim: "\(Int(dcShare * 100)) % DC")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func summaryItem(_ value: String, _ title: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChargeRow: View {
    let charge: Charge

    private var typeColor: Color { charge.isDC ? .red : .green }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(charge.address ?? String(localized: "Unknown location"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(verbatim: charge.isDC ? "DC" : "AC")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(typeColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(typeColor)
                Text(verbatim: "+" + Fmt.kwh(charge.chargeEnergyAdded))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(typeColor)
            }
            Text(verbatim: "\(Fmt.day(charge.startDate)) \(Fmt.time(charge.startDate))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label(Fmt.duration(charge.durationMin), systemImage: "clock")
                if let batt = charge.batteryDetails, let s = batt.startBatteryLevel, let e = batt.endBatteryLevel {
                    Label("\(s) → \(e) %", systemImage: "battery.75percent")
                }
                if let cost = charge.displayCost {
                    Label(Fmt.kr(cost), systemImage: "banknote")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct ChargeDetailView: View {
    let api: APIClient
    let carID: Int
    let chargeID: Int

    @State private var charge: Charge?
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let charge {
                let typeColor: Color = charge.isDC ? .red : .green
                VStack(spacing: 16) {
                    if let lat = charge.latitude, let lon = charge.longitude {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            latitudinalMeters: 1200, longitudinalMeters: 1200
                        ))) {
                            Marker(charge.address ?? "", systemImage: "bolt.fill",
                                   coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                                .tint(typeColor)
                        }
                        .mapControlVisibility(.hidden)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "bolt.fill", title: String(localized: "Added"), value: Fmt.kwh(charge.chargeEnergyAdded), tint: typeColor)
                        StatTile(icon: "bolt.badge.clock", title: String(localized: "Used"), value: Fmt.kwh(charge.chargeEnergyUsed), tint: .orange)
                        StatTile(icon: "gauge.with.dots.needle.100percent", title: String(localized: "Max power"), value: Fmt.kw(charge.maxPowerKw), tint: typeColor)
                        StatTile(icon: "gauge.with.dots.needle.50percent", title: String(localized: "Avg power"), value: Fmt.kw(charge.avgPowerKw), tint: typeColor)
                        StatTile(icon: "battery.75percent", title: String(localized: "Battery"), value: batteryText, tint: .green)
                        StatTile(icon: "clock.fill", title: String(localized: "Charge time"), value: Fmt.duration(charge.durationMin), tint: .secondary)
                        StatTile(icon: "banknote", title: String(localized: "Cost"), value: Fmt.kr(charge.displayCost), tint: .blue)
                        StatTile(icon: "thermometer.medium", title: String(localized: "Outside temp"), value: Fmt.temp(charge.outsideTempAvg), tint: .teal)
                    }

                    if let points = charge.chargeDetails, points.count > 2 {
                        ChargeCurve(points: points, powerColor: typeColor)
                    }
                }
                .padding(.horizontal)
            } else if let error {
                ErrorCard(message: error) { Task { await load() } }
            } else {
                ProgressView().padding(.top, 120)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(charge?.address ?? String(localized: "Charge"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var batteryText: String {
        guard let batt = charge?.batteryDetails, let s = batt.startBatteryLevel, let e = batt.endBatteryLevel else { return "–" }
        return "\(s) → \(e) %"
    }

    private func load() async {
        do {
            charge = try await api.charge(carID: carID, chargeID: chargeID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ChargeCurve: View {
    let points: [ChargePoint]
    var powerColor: Color = .green

    // dedupliserat per tidsstämpel, se SpeedChart
    private var series: [(date: Date, power: Double?, level: Int?)] {
        var byDate: [Date: (power: Double?, level: Int?)] = [:]
        for p in points {
            guard let d = p.date else { continue }
            let old = byDate[d]
            byDate[d] = (power: p.chargerDetails?.chargerPower ?? old?.power, level: p.batteryLevel ?? old?.level)
        }
        return byDate.keys.sorted().map { (date: $0, power: byDate[$0]!.power, level: byDate[$0]!.level) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Charge curve")
                .font(.subheadline.weight(.semibold))
            Chart(series, id: \.date) { point in
                if let power = point.power {
                    LineMark(x: .value("Time", point.date), y: .value("kW", power), series: .value("Series", "Power"))
                        .foregroundStyle(powerColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let level = point.level {
                    LineMark(x: .value("Time", point.date), y: .value("%", Double(level)), series: .value("Series", "Battery"))
                        .foregroundStyle(.blue.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .frame(height: 160)
            HStack(spacing: 16) {
                Label("Power (kW)", systemImage: "line.diagonal").foregroundStyle(powerColor)
                Label("Battery (%)", systemImage: "line.diagonal").foregroundStyle(.blue.opacity(0.6))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
