import SwiftUI
import MapKit
import Charts

// the charges the flow shows, added up. the title is the period they were picked by
struct ChargeSummaryCard: View {
    let title: LocalizedStringKey
    let groups: [ChargeGroup]
    var tessieCosts: [Int: Double] = [:]

    private var cost: Double {
        groups.reduce(0) { $0 + ($1.cost(tessieCosts: tessieCosts) ?? 0) }
    }
    private var energy: Double { groups.compactMap(\.energyAdded).reduce(0, +) }
    private var dcShare: Double {
        guard energy > 0 else { return 0 }
        return groups.filter(\.isDC).compactMap(\.energyAdded).reduce(0, +) / energy
    }
    // taken from the same number so the two halves always make a hundred
    private var dcPercent: Int { Int((dcShare * 100).rounded()) }
    private var acPercent: Int { 100 - dcPercent }
    private var partCount: Int { groups.reduce(0) { $0 + $1.parts.count } }

    private var countValue: String {
        partCount > groups.count ? "\(groups.count) (\(partCount))" : "\(groups.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // each half wears the colour it wears everywhere else in the app
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                (Text(verbatim: "\(acPercent) % AC").foregroundColor(.green)
                    + Text(verbatim: " / ").foregroundColor(.secondary)
                    + Text(verbatim: "\(dcPercent) % DC").foregroundColor(.red))
                    .font(.caption)
            }
            HStack {
                summaryItem(Fmt.kr(cost), String(localized: "Cost", bundle: .current), .blue)
                summaryItem(Fmt.kwh(energy), String(localized: "Energy", bundle: .current), .green)
                // the parenthesis is the processes the joined stretches were made of,
                // and the tint is neutral - grey means time everywhere else
                summaryItem(countValue, String(localized: "Charges", bundle: .current), .primary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // the caption centres under its value - hanging off the left edge read as skew
    private func summaryItem(_ value: String, _ title: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ChargeRow: View {
    let group: ChargeGroup
    var tessieCosts: [Int: Double] = [:]
    // the day is already in the section header when the row sits in the timeline
    var showsDay = true

    private var typeColor: Color { group.isDC ? .red : .green }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.address ?? String(localized: "Unknown location", bundle: .current))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(verbatim: group.isDC ? "DC" : "AC")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(typeColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(typeColor)
                Text(verbatim: "+" + Fmt.kwh(group.energyAdded))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(typeColor)
            }
            Text(verbatim: showsDay
                 ? "\(Fmt.day(group.startDate)) \(Fmt.time(group.startDate))"
                 : "\(Fmt.time(group.startDate)) – \(Fmt.time(group.endDate))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                // a joined stretch shows the hours it stood connected, a single charge
                // its charging time - for one part they are the same thing
                MetricChip(text: Fmt.duration(group.parts.count > 1 ? group.pluggedMinutes : group.chargeMinutes))
                if group.parts.count > 1 {
                    MetricChip(text: "×\(group.parts.count)", icon: "bolt.horizontal.fill", tint: typeColor)
                }
                if let battery = Fmt.battery(group.batteryDetails) {
                    MetricChip(text: battery, tint: .green)
                }
                if let cost = group.cost(tessieCosts: tessieCosts) {
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
    let chargeIDs: [Int]
    var tessieCosts: [Int: Double] = [:]

    @AppStorage(Pref.teslamate.key) private var teslamateURL = Pref.teslamate.value

    @State private var group: ChargeGroup?
    @State private var error: String?
    // precomputed on load, see ChargeCurve.build
    @State private var curve: [ChargeCurve.Sample] = []
    @State private var scrubDate: Date?
    @State private var heldDate: Date?

    // a joined stretch has real gaps in it, so the readout snaps to the nearest
    // sample and the rule follows it rather than the finger - otherwise the line
    // stands in a pause showing the power from before it
    private var scrubSample: ChargeCurve.Sample? {
        guard let heldDate, !curve.isEmpty else { return nil }
        return curve.min { abs($0.date.timeIntervalSince(heldDate)) < abs($1.date.timeIntervalSince(heldDate)) }
    }

    // cost editing is per process in TeslaMate, so the link only fits a single charge
    private var costEditURL: URL? {
        guard chargeIDs.count == 1, let id = chargeIDs.first else { return nil }
        return URL(string: teslamateURL.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)) + "/charge-cost/\(id)")
    }

    var body: some View {
        ScrollView {
            if let group {
                let typeColor: Color = group.isDC ? .red : .green
                VStack(spacing: 16) {
                    if let located = group.parts.first(where: { $0.latitude != nil && $0.longitude != nil }),
                       let lat = located.latitude, let lon = located.longitude {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            latitudinalMeters: 1200, longitudinalMeters: 1200
                        ))) {
                            Marker(group.address ?? "", systemImage: "bolt.fill",
                                   coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                                .tint(typeColor)
                        }
                        .mapControlVisibility(.hidden)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "bolt.fill", title: String(localized: "Added", bundle: .current), value: Fmt.kwh(group.energyAdded), tint: typeColor)
                        StatTile(icon: "bolt.badge.clock", title: String(localized: "Used", bundle: .current), value: Fmt.kwh(group.energyUsed), tint: .orange)
                        StatTile(icon: "arrow.triangle.2.circlepath", title: String(localized: "Efficiency", bundle: .current), value: Fmt.percent(group.efficiency), tint: .mint)
                        StatTile(icon: "gauge.with.dots.needle.100percent", title: String(localized: "Max power", bundle: .current), value: Fmt.kw(group.maxPowerKw), tint: typeColor)
                        StatTile(icon: "gauge.with.dots.needle.50percent", title: String(localized: "Avg power", bundle: .current), value: Fmt.kw(group.avgPowerKw), tint: typeColor)
                        StatTile(icon: "battery.75percent", title: String(localized: "Battery", bundle: .current), value: Fmt.battery(group.batteryDetails) ?? "–", tint: .green)
                        StatTile(icon: "clock.fill", title: String(localized: "Charge time", bundle: .current), value: Fmt.duration(group.chargeMinutes), tint: .secondary)
                        if group.parts.count > 1 {
                            StatTile(icon: "powerplug.fill", title: String(localized: "Plugged in", bundle: .current), value: Fmt.duration(group.pluggedMinutes), tint: .secondary)
                        }
                        let costTitle = group.usesTessieCost(tessieCosts)
                            ? String(localized: "Cost", bundle: .current) + " (Tessie)"
                            : String(localized: "Cost", bundle: .current)
                        let costValue = Fmt.kr(group.cost(tessieCosts: tessieCosts))
                        if let costEditURL {
                            Link(destination: costEditURL) {
                                StatTile(icon: "banknote", title: costTitle, value: costValue, tint: .blue, chevron: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            StatTile(icon: "banknote", title: costTitle, value: costValue, tint: .blue)
                        }
                        StatTile(icon: "thermometer.medium", title: String(localized: "Outside temp", bundle: .current), value: Fmt.temp(group.outsideTempAvg), tint: .teal)
                    }

                    if curve.count > 2 {
                        ChargeCurve(samples: curve, powerColor: typeColor, selection: $scrubDate,
                                    reading: scrubSample)
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
        .task { await load() }
        .onChange(of: scrubDate) { _, new in
            if new != nil { heldDate = new }
        }
    }

    private func load() async {
        do {
            let parts = try await withThrowingTaskGroup(of: Charge.self) { tasks in
                for id in chargeIDs {
                    tasks.addTask { try await api.charge(carID: carID, chargeID: id) }
                }
                var loaded: [Charge] = []
                for try await charge in tasks { loaded.append(charge) }
                return loaded.sorted { $0.startDate < $1.startDate }
            }
            guard !parts.isEmpty else { throw APIError.http(404) }
            group = ChargeGroup(parts: parts)
            curve = ChargeCurve.build(parts)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ChargeCurve: View {
    let samples: [Sample]
    var powerColor: Color = .green
    @Binding var selection: Date?
    var reading: Sample?

    private let levelColor = Color.blue

    struct Sample: Identifiable {
        let date: Date
        let power: Double?
        let level: Int?
        let energy: Double?
        let part: Int

        var id: Date { date }
    }

    // deduplicated per timestamp, see SpeedChart. built on load like the drive
    // detail's series — as a computed property the points re-sorted on every render.
    // the part index keeps the series separate so the line breaks in the gaps
    // between a joined stretch's charges instead of bridging them
    static func build(_ parts: [Charge]) -> [Sample] {
        var samples: [Sample] = []
        var carried = 0.0
        for (index, part) in parts.enumerated() {
            var byDate: [Date: (power: Double?, level: Int?, energy: Double?)] = [:]
            for p in part.chargeDetails ?? [] {
                guard let d = p.date else { continue }
                let old = byDate[d]
                byDate[d] = (power: p.chargerDetails?.chargerPower ?? old?.power,
                             level: p.batteryLevel ?? old?.level,
                             energy: p.chargeEnergyAdded ?? old?.energy)
            }
            let dates = byDate.keys.sorted()
            // each part picks up where the last one ended, which both carries a counter
            // that reset with the cable and closes the tenths of a kilowatt-hour the
            // samples land either side of a boundary. the stretch then ends on exactly
            // what the parts add up to, the same figure the tiles show
            let first = dates.compactMap { byDate[$0]?.energy }.first ?? 0
            let offset = carried - first
            samples += dates.map {
                Sample(date: $0, power: byDate[$0]!.power, level: byDate[$0]!.level,
                       energy: byDate[$0]!.energy.map { $0 + offset }, part: index)
            }
            carried = samples.compactMap(\.energy).last ?? carried
        }
        return samples
    }

    private func readout(_ sample: Sample) -> Text {
        var text = Text(verbatim: Fmt.time(sample.date)).foregroundColor(.secondary)
        if let power = sample.power {
            text = text + Text(verbatim: " · \(Int(power)) kW").foregroundColor(powerColor)
        }
        if let level = sample.level {
            text = text + Text(verbatim: " · \(level) %").foregroundColor(levelColor)
        }
        if let energy = sample.energy {
            text = text + Text(verbatim: " · " + Fmt.kwh(energy)).foregroundColor(.primary)
        }
        return text
    }

    // hour labels alone go in circles once the stretch passes a day
    private var spansDays: Bool {
        guard let first = samples.first?.date, let last = samples.last?.date else { return false }
        return last.timeIntervalSince(first) > 24 * 3600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Charge curve")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let reading {
                    // each figure wears the colour of the line it was read from
                    readout(reading)
                        .font(.caption.weight(.medium).monospacedDigit())
                } else {
                    Text("Drag the chart to read the charge")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            // the marker sits outside the per-point loop - otherwise it draws one RuleMark per point
            Chart {
                ForEach(samples) { point in
                    if let power = point.power {
                        LineMark(x: .value("Time", point.date), y: .value("kW", power), series: .value("Series", "Power-\(point.part)"))
                            .foregroundStyle(powerColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    if let level = point.level {
                        LineMark(x: .value("Time", point.date), y: .value("%", Double(level)), series: .value("Series", "Battery-\(point.part)"))
                            .foregroundStyle(levelColor.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    }
                }
                if let reading {
                    RuleMark(x: .value("Selected", reading.date))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXSelection(value: $selection)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: spansDays ? .dateTime.weekday(.abbreviated).hour() : .dateTime.hour().minute())
                }
            }
            .frame(height: 160)
            HStack(spacing: 16) {
                Label("Power (kW)", systemImage: "line.diagonal").foregroundStyle(powerColor)
                Label("Battery (%)", systemImage: "line.diagonal").foregroundStyle(levelColor.opacity(0.6))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
