import SwiftUI
import MapKit
import Charts

struct DriveRow: View {
    let drive: Drive
    var heaterUsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(Fmt.time(drive.startDate)) – \(Fmt.time(drive.endDate))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: Fmt.distance(drive.distance))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            Text(verbatim: "\(drive.startAddress ?? String(localized: "Unknown")) → \(drive.endAddress ?? String(localized: "Unknown"))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                MetricChip(text: Fmt.duration(drive.durationMin))
                if drive.efficiencyPct != nil {
                    MetricChip(text: Fmt.pct(drive.efficiencyPct, decimals: 0),
                               tint: CarState.efficiencyColor(drive.efficiencyPct))
                }
                if let battery = Fmt.battery(drive.batteryDetails) {
                    MetricChip(text: battery, tint: .green)
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

struct DriveDetailView: View {
    let api: APIClient
    let carID: Int
    let driveID: Int

    @State private var drive: Drive?
    @State private var error: String?
    @State private var scrubDate: Date?
    @State private var heldDate: Date?

    // precomputed on load — recomputing per gesture tick makes scrubbing sluggish on long drives
    @State private var track: [CLLocationCoordinate2D] = []
    @State private var scrubPoints: [DrivePoint] = []
    @State private var series: [SpeedPoint] = []
    @State private var elevation: [ElevationPoint] = []

    private var scrubPoint: DrivePoint? {
        guard let heldDate, !scrubPoints.isEmpty else { return nil }
        return scrubPoints
            .min { abs($0.date!.timeIntervalSince(heldDate)) < abs($1.date!.timeIntervalSince(heldDate)) }
    }

    var body: some View {
        ScrollView {
            if let drive {
                VStack(spacing: 16) {
                    if track.count > 1 {
                        Map {
                            MapPolyline(coordinates: track)
                                .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            if let first = track.first {
                                Marker("Start", systemImage: "flag.fill", coordinate: first).tint(.green)
                            }
                            if let last = track.last {
                                Marker("Finish", systemImage: "flag.checkered", coordinate: last).tint(.red)
                            }
                            if let p = scrubPoint, let lat = p.latitude, let lon = p.longitude {
                                Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                                    ZStack {
                                        Circle().fill(.white)
                                        Circle().fill(.blue).padding(3)
                                    }
                                    .frame(width: 20, height: 20)
                                    .shadow(radius: 2)
                                }
                            }
                        }
                        .mapControlVisibility(.hidden)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    if series.count > 2 {
                        SpeedChart(series: series, selection: $scrubDate, marker: heldDate, label: scrubPoint.map(scrubLabel))
                    }
                    if elevation.count > 2 {
                        ElevationChart(series: elevation, selection: $scrubDate, marker: heldDate)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "point.topleft.down.to.point.bottomright.curvepath", title: String(localized: "Distance"), value: Fmt.distance(drive.distance), tint: .blue)
                        StatTile(icon: "clock.fill", title: String(localized: "Duration"), value: Fmt.duration(drive.durationMin), tint: .secondary)
                        SplitStatTile(
                            leading: .init(icon: "bolt.fill", title: String(localized: "Energy (net)"),
                                           value: Fmt.energy(drive.energyConsumedNet), tint: .orange),
                            trailing: .init(icon: "arrow.counterclockwise", title: String(localized: "Regen"),
                                            value: Fmt.energy(drive.regenKWh), tint: .green))
                        StatTile(icon: "bolt.car.fill", title: String(localized: "Consumption"), value: Fmt.consumption(drive.consumptionWhPerKm), tint: .purple)
                        StatTile(icon: "leaf.fill", title: String(localized: "Efficiency"), value: Fmt.pct(drive.efficiencyPct, decimals: 0),
                                 tint: CarState.efficiencyColor(drive.efficiencyPct),
                                 valueTint: CarState.efficiencyColor(drive.efficiencyPct))
                        StatTile(icon: "gauge.with.dots.needle.67percent", title: String(localized: "Max / avg"), value: Fmt.speedPair(drive.speedMax, drive.speedAvg), tint: .orange)
                        StatTile(icon: "battery.75percent", title: String(localized: "Battery"), value: Fmt.battery(drive.batteryDetails) ?? "–", tint: .green)
                        StatTile(icon: "thermometer.medium", title: String(localized: "Outside temp"), value: Fmt.temp(drive.outsideTempAvg), tint: .teal)
                        if drive.batteryHeaterUsed {
                            StatTile(icon: "heat.waves", title: String(localized: "Battery heater"),
                                     value: String(localized: "On during the drive"), tint: .red, valueTint: .red)
                        }
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
            let loaded = try await api.drive(carID: carID, driveID: driveID)
            let points = loaded.driveDetails ?? []
            drive = loaded
            track = points.compactMap { p in
                guard let lat = p.latitude, let lon = p.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            scrubPoints = points.filter { $0.date != nil && $0.latitude != nil && $0.longitude != nil }
            series = Self.buildSeries(points)
            elevation = Self.buildElevation(points)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func scrubLabel(_ p: DrivePoint) -> String {
        var parts = [Fmt.time(p.date)]
        if let speed = p.speed { parts.append(Fmt.speed(speed)) }
        if let power = p.power { parts.append("\(Int(power)) kW") }
        if let level = p.batteryLevel { parts.append("\(level) %") }
        return parts.joined(separator: " · ")
    }

    // deduplicate per timestamp (AreaMark stacks them otherwise) and downsample for rendering
    static func buildSeries(_ points: [DrivePoint]) -> [SpeedPoint] {
        var byDate: [Date: Double] = [:]
        for p in points {
            guard let d = p.date, let s = p.speed else { continue }
            byDate[d] = max(byDate[d] ?? 0, s)
        }
        var series = byDate.keys.sorted().map { SpeedPoint(date: $0, speed: byDate[$0]!) }
        if series.count > 1600 {
            let step = series.count / 1600 + 1
            series = series.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
        }
        return series
    }

    // the GPS altitude is noisy enough to dip below the sea along the coast, so every
    // point becomes the mean of its neighbours within fifteen seconds. a hill lasts
    // minutes and survives that; the spikes do not. null points are skipped, not zeroed
    static func buildElevation(_ points: [DrivePoint]) -> [ElevationPoint] {
        var byDate: [Date: Double] = [:]
        for p in points {
            guard let d = p.date, let e = p.elevation, byDate[d] == nil else { continue }
            byDate[d] = e
        }
        let raw = byDate.keys.sorted().map { ElevationPoint(date: $0, metres: byDate[$0]!) }
        guard raw.count > 2 else { return [] }

        let window: TimeInterval = 15
        var smoothed: [ElevationPoint] = []
        smoothed.reserveCapacity(raw.count)
        var lo = 0, hi = 0, sum = 0.0
        for p in raw {
            while hi < raw.count, raw[hi].date.timeIntervalSince(p.date) <= window {
                sum += raw[hi].metres
                hi += 1
            }
            while p.date.timeIntervalSince(raw[lo].date) > window {
                sum -= raw[lo].metres
                lo += 1
            }
            smoothed.append(ElevationPoint(date: p.date, metres: sum / Double(hi - lo)))
        }
        if smoothed.count > 1600 {
            let step = smoothed.count / 1600 + 1
            smoothed = smoothed.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
        }
        return smoothed
    }
}

struct SpeedPoint: Identifiable {
    let date: Date
    let speed: Double

    var id: Date { date }
}

struct ElevationPoint: Identifiable {
    let date: Date
    let metres: Double

    var id: Date { date }
}

struct ElevationChart: View {
    let series: [ElevationPoint]
    @Binding var selection: Date?
    var marker: Date?

    private var floor: Double { series.map(\.metres).min() ?? 0 }
    private var ceiling: Double { series.map(\.metres).max() ?? 0 }

    // the metres climbed and the metres dropped, summed over the smoothed line
    private var climb: (up: Double, down: Double) {
        var up = 0.0, down = 0.0
        for (a, b) in zip(series, series.dropFirst()) {
            let delta = b.metres - a.metres
            if delta > 0 { up += delta } else { down -= delta }
        }
        return (up, down)
    }

    // what the two add up to: how much higher or lower the drive ended than it began
    private var net: String {
        let value = climb.up - climb.down
        let sign = value.rounded() > 0 ? "+" : value.rounded() < 0 ? "\u{2212}" : "\u{00B1}"
        return sign + Fmt.altitude(abs(value))
    }

    private var atMarker: Double? {
        guard let marker else { return nil }
        return series.min { abs($0.date.timeIntervalSince(marker)) < abs($1.date.timeIntervalSince(marker)) }?.metres
    }

    var body: some View {
        // the axis follows the terrain, not the sea: a drive between twenty and sixty
        // metres would be a flat line on a scale that starts at zero
        let pad = max(5, (ceiling - floor) * 0.15)
        let low = floor - pad
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Elevation")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let atMarker {
                    Text(verbatim: Fmt.altitude(atMarker))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.brown)
                } else {
                    Text(verbatim: "↑ \(Fmt.altitude(climb.up))  ↓ \(Fmt.altitude(climb.down))  Δ \(net)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(series) { point in
                    AreaMark(x: .value("Time", point.date),
                             yStart: .value("Floor" as String, Units.altitude(low)),
                             yEnd: .value("Elevation" as String, Units.altitude(point.metres)))
                        .foregroundStyle(.brown.opacity(0.15).gradient)
                    LineMark(x: .value("Time", point.date), y: .value("Elevation" as String, Units.altitude(point.metres)))
                        .foregroundStyle(.brown)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let marker {
                    RuleMark(x: .value("Selected" as String, marker))
                        .foregroundStyle(.brown.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartYScale(domain: Units.altitude(low)...Units.altitude(ceiling + pad))
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3))
            }
            .chartXSelection(value: $selection)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .frame(height: 120)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SpeedChart: View {
    let series: [SpeedPoint]
    @Binding var selection: Date?
    var marker: Date?
    var label: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Speed")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let label {
                    Text(verbatim: label)
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.blue)
                } else {
                    Text("Drag the chart to follow the drive")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            // the marker sits outside the per-point loop - otherwise it draws one RuleMark per point
            Chart {
                ForEach(series) { point in
                    AreaMark(x: .value("Time", point.date), y: .value("Speed" as String, Units.distance(point.speed)))
                        .foregroundStyle(.blue.opacity(0.15).gradient)
                    LineMark(x: .value("Time", point.date), y: .value("Speed" as String, Units.distance(point.speed)))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let marker {
                    RuleMark(x: .value("Selected" as String, marker))
                        .foregroundStyle(.blue.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXSelection(value: $selection)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
