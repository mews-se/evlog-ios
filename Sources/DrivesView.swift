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
                Text(verbatim: Fmt.km(drive.distance))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            Text(verbatim: "\(drive.startAddress ?? String(localized: "Unknown", bundle: .current)) → \(drive.endAddress ?? String(localized: "Unknown", bundle: .current))")
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

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "point.topleft.down.to.point.bottomright.curvepath", title: String(localized: "Distance", bundle: .current), value: Fmt.km(drive.distance), tint: .blue)
                        StatTile(icon: "clock.fill", title: String(localized: "Duration", bundle: .current), value: Fmt.duration(drive.durationMin), tint: .secondary)
                        SplitStatTile(
                            leading: .init(icon: "bolt.fill", title: String(localized: "Energy (net)", bundle: .current),
                                           value: Fmt.energy(drive.energyConsumedNet), tint: .orange),
                            trailing: .init(icon: "arrow.counterclockwise", title: String(localized: "Regen", bundle: .current),
                                            value: Fmt.energy(drive.regenKWh), tint: .green))
                        StatTile(icon: "bolt.car.fill", title: String(localized: "Consumption", bundle: .current), value: Fmt.consumption(drive.consumptionWhPerKm), tint: .purple)
                        StatTile(icon: "leaf.fill", title: String(localized: "Efficiency", bundle: .current), value: Fmt.pct(drive.efficiencyPct, decimals: 0),
                                 tint: CarState.efficiencyColor(drive.efficiencyPct),
                                 valueTint: CarState.efficiencyColor(drive.efficiencyPct))
                        StatTile(icon: "gauge.with.dots.needle.67percent", title: String(localized: "Max / avg", bundle: .current), value: "\(Int(drive.speedMax ?? 0)) / \(Int(drive.speedAvg ?? 0)) km/h", tint: .orange)
                        StatTile(icon: "battery.75percent", title: String(localized: "Battery", bundle: .current), value: Fmt.battery(drive.batteryDetails) ?? "–", tint: .green)
                        StatTile(icon: "thermometer.medium", title: String(localized: "Outside temp", bundle: .current), value: Fmt.temp(drive.outsideTempAvg), tint: .teal)
                        if drive.batteryHeaterUsed {
                            StatTile(icon: "heat.waves", title: String(localized: "Battery heater", bundle: .current),
                                     value: String(localized: "On during the drive", bundle: .current), tint: .red, valueTint: .red)
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
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func scrubLabel(_ p: DrivePoint) -> String {
        var parts = [Fmt.time(p.date)]
        if let speed = p.speed { parts.append("\(Int(speed)) km/h") }
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
}

struct SpeedPoint: Identifiable {
    let date: Date
    let speed: Double

    var id: Date { date }
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
                    AreaMark(x: .value("Time", point.date), y: .value("km/h" as String, point.speed))
                        .foregroundStyle(.blue.opacity(0.15).gradient)
                    LineMark(x: .value("Time", point.date), y: .value("km/h" as String, point.speed))
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
