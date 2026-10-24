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
                summaryItem(Fmt.cost(cost), String(localized: "Cost"), .blue)
                summaryItem(Fmt.kwh(energy), String(localized: "Energy"), .green)
                // the parenthesis is the processes the joined stretches were made of,
                // and the tint is neutral - grey means time everywhere else
                summaryItem(countValue, String(localized: "Charges"), .primary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // the caption centres under its value - hanging off the left edge read as skew
    private func summaryItem(_ value: String, _ title: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(verbatim: title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ChargeRow: View {
    let group: ChargeGroup
    var tessieCosts: [Int: Double] = [:]
    // in the timeline the day is the section header, so the place is the headline. in
    // a place's own list the place is the title, so the day takes the headline instead
    var showsPlace = true
    var heaterUsed = false

    private var typeColor: Color { group.isDC ? .red : .green }

    private var headline: String {
        showsPlace
            ? group.address ?? String(localized: "Unknown location")
            : Fmt.day(group.startDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: headline)
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
            Text(verbatim: "\(Fmt.time(group.startDate)) – \(Fmt.time(group.endDate))")
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
                    MetricChip(text: Fmt.cost(cost), tint: .blue)
                }
                if heaterUsed {
                    MetricChip(icon: "heat.waves", tint: .red)
                        .accessibilityLabel(Text("Battery heater"))
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
    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value

    @State private var group: ChargeGroup?
    @State private var climateMinutes: Double?
    @State private var error: String?
    // precomputed on load, see ChargeCurve.build
    @State private var curve: [ChargeCurve.Sample] = []
    @State private var pace: [ChargePaceCard.Fact]?
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
        let root = teslamateURL.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        guard !root.isEmpty, chargeIDs.count == 1, let id = chargeIDs.first,
              let url = URL(string: root + "/charge-cost/\(id)"),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
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
                        StatTile(icon: "bolt.fill", title: String(localized: "Added"), value: Fmt.kwh(group.energyAdded), tint: typeColor)
                        StatTile(icon: "bolt.badge.clock", title: String(localized: "Used"), value: Fmt.kwh(group.energyUsed), tint: .orange)
                        StatTile(icon: "arrow.triangle.2.circlepath", title: String(localized: "Efficiency"), value: Fmt.ratio(group.efficiency), tint: .mint)
                        StatTile(icon: "gauge.with.dots.needle.100percent", title: String(localized: "Max power"), value: Fmt.kw(group.maxPowerKw), tint: typeColor)
                        StatTile(icon: "gauge.with.dots.needle.50percent", title: String(localized: "Avg power"), value: Fmt.kw(group.avgPowerKw), tint: typeColor)
                        StatTile(icon: "battery.75percent", title: String(localized: "Battery"), value: Fmt.battery(group.batteryDetails) ?? "–", tint: .green)
                        StatTile(icon: "clock.fill", title: String(localized: "Charge time"), value: Fmt.duration(group.chargeMinutes), tint: .secondary)
                        if group.parts.count > 1 {
                            StatTile(icon: "powerplug.fill", title: String(localized: "Plugged in"), value: Fmt.duration(group.pluggedMinutes), tint: .secondary)
                        }
                        let costTitle = group.usesTessieCost(tessieCosts)
                            ? String(localized: "Cost") + " (Tessie)"
                            : String(localized: "Cost")
                        let costValue = Fmt.cost(group.cost(tessieCosts: tessieCosts))
                        if let costEditURL {
                            Link(destination: costEditURL) {
                                StatTile(icon: "banknote", title: costTitle, value: costValue, tint: .blue, chevron: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            StatTile(icon: "banknote", title: costTitle, value: costValue, tint: .blue)
                        }
                        StatTile(icon: "thermometer.medium", title: String(localized: "Outside temp"), value: Fmt.temp(group.outsideTempAvg), tint: .teal)
                        if let heater = group.batteryHeaterMinutes {
                            StatTile(icon: "heat.waves", title: String(localized: "Battery heater"), value: Fmt.duration(heater), tint: .red)
                        }
                        // read at five minute intervals, so the figure is a rough one
                        if let climate = climateMinutes, climate > 0 {
                            StatTile(icon: "fan.fill", title: String(localized: "Climate"), value: "~" + Fmt.duration(climate), tint: .cyan)
                        }
                    }

                    if let pace {
                        ChargePaceCard(facts: pace)
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
            pace = group.flatMap { ChargePaceCard.facts(for: $0) }
        } catch {
            self.error = error.localizedDescription
        }
        // the cabin draw is only visible through Grafana - additive, never blocking
        if let group, let end = group.endDate {
            climateMinutes = try? await GrafanaClient(baseURL: grafanaURL)
                .climateMinutes(carID: carID, from: group.startDate, to: end)
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
                        LineMark(x: .value("Time", point.date), y: .value("kW" as String, power), series: .value("Series" as String, "Power-\(point.part)"))
                            .foregroundStyle(powerColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    if let level = point.level {
                        LineMark(x: .value("Time", point.date), y: .value("%" as String, Double(level)), series: .value("Series" as String, "Battery-\(point.part)"))
                            .foregroundStyle(levelColor.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    }
                }
                if let reading {
                    RuleMark(x: .value("Selected" as String, reading.date))
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

// what the log shows about the pace of a charge: on AC the current on offer against the
// current drawn, on DC what the car itself does to hold the power back. nothing is judged
// against the site or the car's best, and a shared stall leaves no trace to name
struct ChargePaceCard: View {
    struct Fact: Identifiable {
        let icon: String
        let tint: Color
        let text: String
        var detail: String?

        var id: String { text }
    }

    let facts: [Fact]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What set the pace")
                .font(.subheadline.weight(.semibold))
            ForEach(facts) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: fact.icon)
                        .foregroundStyle(fact.tint)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: fact.text)
                            .font(.subheadline)
                        if let detail = fact.detail {
                            Text(verbatim: detail)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private typealias Sample = (date: Date, point: ChargePoint)

    // nil when the log holds no samples to read
    static func facts(for group: ChargeGroup) -> [Fact]? {
        let parts: [[Sample]] = group.parts.map { part in
            (part.chargeDetails ?? [])
                .compactMap { p in p.date.map { (date: $0, point: p) } }
                .sorted { $0.date < $1.date }
        }
        guard parts.contains(where: { !$0.isEmpty }) else { return nil }
        var facts: [Fact] = []

        let offer = group.isDC ? nil : Offer(parts.flatMap { $0 }.map(\.point))
        if let offer { facts.append(offer.fact) }

        if let first = parts.first?.first?.point, let level = first.batteryLevel,
           let usable = first.usableBatteryLevel, level > usable {
            let usableText = "\(usable) %", levelText = "\(level) %"
            facts.append(Fact(icon: "snowflake", tint: .cyan,
                              text: String(localized: "The battery started cold"),
                              detail: String(localized: "\(usableText) usable of \(levelText)")))
        }

        // a warm pack heats for a minute or two and the line ends there. it earns a line
        // when it ran for half the charge or more, or while the power was held back
        let climb = group.isDC ? heatedClimb(parts) : nil
        let drewLess = offer.map { $0.drawn < $0.pilot - 1 } ?? false
        if let heater = group.batteryHeaterMinutes, heater >= 5, let minutes = group.chargeMinutes,
           heater * 2 >= minutes || drewLess || climb != nil {
            let heaterText = Fmt.duration(heater), minutesText = Fmt.duration(minutes)
            facts.append(Fact(icon: "heat.waves", tint: .red,
                              text: String(localized: "The battery heater ran for \(heaterText) of \(minutesText)"),
                              detail: climb.map {
                                  let climbText = Fmt.duration($0.minutes), peakText = Fmt.kw($0.peak)
                                  return String(localized: "The power took \(climbText) to climb to \(peakText)")
                              }))
        }

        if parts.joined().contains(where: { $0.point.notEnoughPowerToHeat == true }) {
            facts.append(Fact(icon: "thermometer.snowflake", tint: .cyan,
                              text: String(localized: "The charger gave too little power to heat the battery")))
        }

        if group.isDC, let start = group.batteryDetails?.startBatteryLevel, start >= 50 {
            let startText = "\(start) %"
            facts.append(Fact(icon: "battery.75percent", tint: .green,
                              text: String(localized: "Started at \(startText), where the car itself holds the power back")))
        }

        // the parts of an AC stretch are standby top-ups, not stops
        if group.isDC {
            let stops = stops(group, parts)
            if stops.count > 0 {
                let text = stops.count == 1
                    ? String(localized: "Charging stopped once and started again")
                    : String(localized: "Charging stopped \(stops.count) times and started again")
                let idleText = Fmt.duration(max(1, stops.minutes.rounded()))
                facts.append(Fact(icon: "pause.circle", tint: .orange, text: text,
                                  detail: String(localized: "\(idleText) without charging")))
            }
        }

        if facts.isEmpty {
            facts.append(Fact(icon: "checkmark.circle", tint: .secondary,
                              text: String(localized: "Nothing stands out in the log")))
        }
        return facts
    }

    private struct Offer {
        let pilot: Int
        let drawn: Int
        let volts: Int
        let phases: Int

        init?(_ points: [ChargePoint]) {
            let drawing = points.compactMap { p -> (power: Double, pilot: Int, drawn: Int, volts: Int)? in
                guard let d = p.chargerDetails, let power = d.chargerPower, power > 0,
                      let pilot = d.chargerPilotCurrent, pilot > 0,
                      let drawn = d.chargerActualCurrent, drawn > 0,
                      let volts = d.chargerVoltage, volts > 0 else { return nil }
                return (power, pilot, drawn, volts)
            }
            guard let pilot = ChargePaceCard.median(drawing.map(\.pilot)),
                  let drawn = ChargePaceCard.median(drawing.map(\.drawn)),
                  let volts = ChargePaceCard.median(drawing.map(\.volts))
            else { return nil }
            self.pilot = pilot
            self.drawn = drawn
            self.volts = volts
            // the reported phase count reads two on three phases for some cars, so the
            // count comes from what the current and voltage make of the power. summed,
            // the whole kilowatts of the ramp's few samples weigh next to nothing
            let watts = drawing.reduce(0) { $0 + $1.power * 1000 }
            let voltAmps = drawing.reduce(0) { $0 + Double($1.drawn * $1.volts) }
            phases = min(3, max(1, Int((watts / voltAmps).rounded())))
        }

        var fact: Fact {
            let phaseText: String
            switch phases {
            case 1: phaseText = String(localized: "one phase")
            case 2: phaseText = String(localized: "two phases")
            default: phaseText = String(localized: "three phases")
            }
            let factors = phases == 1 ? "\(drawn) A × \(volts) V" : "\(drawn) A × \(phases) × \(volts) V"
            return Fact(icon: "powerplug.fill", tint: .green,
                        text: String(localized: "The charger offered \(pilot) A on \(phaseText) and the car drew \(drawn) A"),
                        detail: factors + " ≈ " + Fmt.kw(Double(drawn * phases * volts) / 1000))
        }
    }

    private static func median<T: Comparable>(_ values: [T]) -> T? {
        values.isEmpty ? nil : values.sorted()[values.count / 2]
    }

    private static func power(_ sample: Sample) -> Double? {
        sample.point.chargerDetails?.chargerPower
    }

    // a warm pack reaches nine tenths of its peak within a minute. two or more with
    // the heater running is the car warming the pack as it goes
    private static func heatedClimb(_ parts: [[Sample]]) -> (minutes: Double, peak: Double)? {
        for samples in parts {
            let powered = samples.filter { (power($0) ?? 0) > 0 }
            guard let start = powered.first?.date,
                  let peak = powered.compactMap(power).max(),
                  let top = powered.first(where: { (power($0) ?? 0) >= peak * 0.9 })?.date
            else { continue }
            let seconds = top.timeIntervalSince(start)
            let heated = powered.contains { $0.date < top && $0.point.batteryInfo?.heaterRunning == true }
            if seconds >= 120, heated { return (seconds / 60, peak) }
        }
        return nil
    }

    // a stretch joined from several processes stopped between them. inside one, power
    // at zero between powered samples is a stop, and so is a gap the level did not
    // climb across - a gap it did climb across is the log going quiet, not the charger
    private static func stops(_ group: ChargeGroup, _ parts: [[Sample]]) -> (count: Int, minutes: Double) {
        var count = group.parts.count - 1
        var seconds = zip(group.parts, group.parts.dropFirst()).reduce(0.0) { sum, pair in
            guard let end = pair.0.endDate else { return sum }
            return sum + max(0, pair.1.startDate.timeIntervalSince(end))
        }
        for samples in parts {
            let powered = samples.indices.filter { (power(samples[$0]) ?? 0) > 0 }
            guard let first = powered.first, let last = powered.last, first < last else { continue }
            var stoppedAt: Date?
            for i in (first + 1)...last {
                let previous = samples[i - 1], current = samples[i]
                if power(current) == 0 {
                    if stoppedAt == nil {
                        stoppedAt = current.date
                        count += 1
                    }
                } else if let stop = stoppedAt {
                    seconds += current.date.timeIntervalSince(stop)
                    stoppedAt = nil
                } else if current.date.timeIntervalSince(previous.date) >= 120,
                          let before = previous.point.batteryLevel, let after = current.point.batteryLevel,
                          after <= before {
                    count += 1
                    seconds += current.date.timeIntervalSince(previous.date)
                }
            }
        }
        return (count, seconds / 60)
    }
}
