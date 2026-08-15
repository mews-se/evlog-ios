import SwiftUI
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
                        ForEach(charges) { charge in
                            NavigationLink(value: charge.chargeId) {
                                ChargeRow(charge: charge)
                            }
                        }
                    }
                    .navigationDestination(for: Int.self) { chargeID in
                        ChargeDetailView(api: api, carID: carID, chargeID: chargeID)
                    }
                } else if let error {
                    ErrorCard(message: error) { Task { await load() } }
                } else if loaded {
                    ContentUnavailableView("Inga laddningar än", systemImage: "bolt.fill")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Laddning")
            .refreshable { await load() }
            .task { if !loaded { await load() } }
        }
    }

    private func load() async {
        do {
            charges = try await api.charges(carID: carID)
            error = nil
        } catch {
            if charges.isEmpty { self.error = error.localizedDescription }
        }
        loaded = true
    }
}

struct ChargeRow: View {
    let charge: Charge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(charge.address ?? "Okänd plats")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("+" + Fmt.kwh(charge.chargeEnergyAdded))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            Text("\(Fmt.day(charge.startDate)) \(Fmt.time(charge.startDate))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label(Fmt.duration(charge.durationMin), systemImage: "clock")
                if let batt = charge.batteryDetails, let s = batt.startBatteryLevel, let e = batt.endBatteryLevel {
                    Label("\(s) → \(e) %", systemImage: "battery.75percent")
                }
                if let cost = charge.cost, cost > 0 {
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
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "bolt.fill", title: "Tillagt", value: Fmt.kwh(charge.chargeEnergyAdded), tint: .green)
                        StatTile(icon: "bolt.badge.clock", title: "Använt", value: Fmt.kwh(charge.chargeEnergyUsed), tint: .orange)
                        StatTile(icon: "battery.75percent", title: "Batteri", value: batteryText, tint: .green)
                        StatTile(icon: "clock.fill", title: "Laddtid", value: Fmt.duration(charge.durationMin), tint: .secondary)
                        StatTile(icon: "banknote", title: "Kostnad", value: Fmt.kr(charge.cost), tint: .blue)
                        StatTile(icon: "thermometer.medium", title: "Utetemp", value: Fmt.temp(charge.outsideTempAvg), tint: .teal)
                    }

                    if let points = charge.chargeDetails, points.count > 2 {
                        ChargeCurve(points: points)
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
        .navigationTitle(charge?.address ?? "Laddning")
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
            Text("Laddkurva")
                .font(.subheadline.weight(.semibold))
            Chart(series, id: \.date) { point in
                if let power = point.power {
                    LineMark(x: .value("Tid", point.date), y: .value("kW", power), series: .value("Serie", "Effekt"))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let level = point.level {
                    LineMark(x: .value("Tid", point.date), y: .value("%", Double(level)), series: .value("Serie", "Batteri"))
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
                Label("Effekt (kW)", systemImage: "line.diagonal").foregroundStyle(.green)
                Label("Batteri (%)", systemImage: "line.diagonal").foregroundStyle(.blue.opacity(0.6))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
