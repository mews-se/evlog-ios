import SwiftUI
import MapKit
import Charts

struct YearSummaryCard: View {
    let charges: [Charge]
    var tessieCosts: [Int: Double] = [:]

    private var year: [Charge] {
        charges.filter { Calendar.current.isDate($0.startDate, equalTo: .now, toGranularity: .year) }
    }

    private var cost: Double {
        year.reduce(0) { $0 + ($1.displayCost ?? tessieCosts[$1.chargeId] ?? 0) }
    }
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
                summaryItem(Fmt.kr(cost), String(localized: "Cost", bundle: .current), .blue)
                summaryItem(Fmt.kwh(energy), String(localized: "Energy", bundle: .current), .green)
                summaryItem("\(year.count)", String(localized: "Charges", bundle: .current), .secondary)
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
    var tessieCost: Double? = nil
    // the day is already in the section header when the row sits in the timeline
    var showsDay = true

    private var typeColor: Color { charge.isDC ? .red : .green }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(charge.address ?? String(localized: "Unknown location", bundle: .current))
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
            Text(verbatim: showsDay
                 ? "\(Fmt.day(charge.startDate)) \(Fmt.time(charge.startDate))"
                 : "\(Fmt.time(charge.startDate)) – \(Fmt.time(charge.endDate))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                MetricChip(text: Fmt.duration(charge.durationMin))
                if let battery = Fmt.battery(charge.batteryDetails) {
                    MetricChip(text: battery, tint: .green)
                }
                if let cost = charge.displayCost ?? tessieCost {
                    MetricChip(text: Fmt.kr(cost), tint: .blue)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ChargeDetailView: View {
    let api: APIClient
    let carID: Int
    let chargeID: Int
    var tessieCost: Double? = nil

    @AppStorage(Pref.teslamate.key) private var teslamateURL = Pref.teslamate.value

    @State private var charge: Charge?
    @State private var error: String?
    // precomputed on load, see ChargeCurve.build
    @State private var curve: [ChargeCurve.Sample] = []

    private var costEditURL: URL? {
        URL(string: teslamateURL.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)) + "/charge-cost/\(chargeID)")
    }

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
                        StatTile(icon: "bolt.fill", title: String(localized: "Added", bundle: .current), value: Fmt.kwh(charge.chargeEnergyAdded), tint: typeColor)
                        StatTile(icon: "bolt.badge.clock", title: String(localized: "Used", bundle: .current), value: Fmt.kwh(charge.chargeEnergyUsed), tint: .orange)
                        StatTile(icon: "arrow.triangle.2.circlepath", title: String(localized: "Efficiency", bundle: .current), value: Fmt.percent(charge.efficiency), tint: .mint)
                        StatTile(icon: "gauge.with.dots.needle.100percent", title: String(localized: "Max power", bundle: .current), value: Fmt.kw(charge.maxPowerKw), tint: typeColor)
                        StatTile(icon: "gauge.with.dots.needle.50percent", title: String(localized: "Avg power", bundle: .current), value: Fmt.kw(charge.avgPowerKw), tint: typeColor)
                        StatTile(icon: "battery.75percent", title: String(localized: "Battery", bundle: .current), value: Fmt.battery(charge.batteryDetails) ?? "–", tint: .green)
                        StatTile(icon: "clock.fill", title: String(localized: "Charge time", bundle: .current), value: Fmt.duration(charge.durationMin), tint: .secondary)
                        let costTitle = charge.displayCost == nil && tessieCost != nil
                            ? String(localized: "Cost", bundle: .current) + " (Tessie)"
                            : String(localized: "Cost", bundle: .current)
                        let costValue = Fmt.kr(charge.displayCost ?? tessieCost)
                        if let costEditURL {
                            Link(destination: costEditURL) {
                                StatTile(icon: "banknote", title: costTitle, value: costValue, tint: .blue, chevron: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            StatTile(icon: "banknote", title: costTitle, value: costValue, tint: .blue)
                        }
                        StatTile(icon: "thermometer.medium", title: String(localized: "Outside temp", bundle: .current), value: Fmt.temp(charge.outsideTempAvg), tint: .teal)
                    }

                    if curve.count > 2 {
                        ChargeCurve(samples: curve, powerColor: typeColor)
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
        .navigationTitle(charge?.address ?? String(localized: "Charge", bundle: .current))
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
        .task { await load() }
    }

    private func load() async {
        do {
            let loaded = try await api.charge(carID: carID, chargeID: chargeID)
            charge = loaded
            curve = ChargeCurve.build(loaded.chargeDetails ?? [])
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ChargeCurve: View {
    let samples: [Sample]
    var powerColor: Color = .green

    struct Sample: Identifiable {
        let date: Date
        let power: Double?
        let level: Int?

        var id: Date { date }
    }

    // deduplicated per timestamp, see SpeedChart. built on load like the drive
    // detail's series — as a computed property the points re-sorted on every render
    static func build(_ points: [ChargePoint]) -> [Sample] {
        var byDate: [Date: (power: Double?, level: Int?)] = [:]
        for p in points {
            guard let d = p.date else { continue }
            let old = byDate[d]
            byDate[d] = (power: p.chargerDetails?.chargerPower ?? old?.power, level: p.batteryLevel ?? old?.level)
        }
        return byDate.keys.sorted().map { Sample(date: $0, power: byDate[$0]!.power, level: byDate[$0]!.level) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Charge curve")
                .font(.subheadline.weight(.semibold))
            Chart(samples) { point in
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
