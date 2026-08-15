import SwiftUI
import MapKit
import Charts

struct DrivesView: View {
    let api: APIClient
    let carID: Int

    @State private var drives: [Drive] = []
    @State private var error: String?
    @State private var loaded = false

    private var grouped: [(day: Date, drives: [Drive])] {
        Dictionary(grouping: drives) { Calendar.current.startOfDay(for: $0.startDate) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, drives: $0.value.sorted { $0.startDate > $1.startDate }) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !drives.isEmpty {
                    List {
                        ForEach(grouped, id: \.day) { group in
                            Section(Fmt.day(group.day)) {
                                ForEach(group.drives) { drive in
                                    NavigationLink(value: drive.driveId) {
                                        DriveRow(drive: drive)
                                    }
                                }
                            }
                        }
                    }
                    .navigationDestination(for: Int.self) { driveID in
                        DriveDetailView(api: api, carID: carID, driveID: driveID)
                    }
                } else if let error {
                    ErrorCard(message: error) { Task { await load() } }
                } else if loaded {
                    ContentUnavailableView("No drives yet", systemImage: "road.lanes")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Drives")
            .refreshable { await load() }
            .task { if !loaded { await load() } }
        }
    }

    private func load() async {
        do {
            drives = try await api.drives(carID: carID)
            error = nil
        } catch {
            if drives.isEmpty { self.error = error.localizedDescription }
        }
        loaded = true
    }
}

struct DriveRow: View {
    let drive: Drive

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(Fmt.time(drive.startDate)) – \(Fmt.time(drive.endDate))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Fmt.km(drive.distance))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            Text(verbatim: "\(drive.startAddress ?? String(localized: "Unknown")) → \(drive.endAddress ?? String(localized: "Unknown"))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 12) {
                Label(Fmt.duration(drive.durationMin), systemImage: "clock")
                Label(Fmt.consumption(drive.consumptionNet), systemImage: "bolt")
                if let batt = drive.batteryDetails, let s = batt.startBatteryLevel, let e = batt.endBatteryLevel {
                    Label("\(s) → \(e) %", systemImage: "battery.75percent")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .labelStyle(.titleAndIcon)
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

    private var track: [CLLocationCoordinate2D] {
        (drive?.driveDetails ?? []).compactMap { point in
            guard let lat = point.latitude, let lon = point.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    private var scrubPoint: DrivePoint? {
        guard let heldDate, let points = drive?.driveDetails else { return nil }
        return points
            .filter { $0.date != nil && $0.latitude != nil && $0.longitude != nil }
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

                    if let points = drive.driveDetails, points.count > 2 {
                        SpeedChart(points: points, selection: $scrubDate, display: heldDate)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "point.topleft.down.to.point.bottomright.curvepath", title: String(localized: "Distance"), value: Fmt.km(drive.distance), tint: .blue)
                        StatTile(icon: "clock.fill", title: String(localized: "Duration"), value: Fmt.duration(drive.durationMin), tint: .secondary)
                        StatTile(icon: "gauge.with.dots.needle.67percent", title: String(localized: "Max / avg"), value: "\(Int(drive.speedMax ?? 0)) / \(Int(drive.speedAvg ?? 0)) km/h", tint: .orange)
                        StatTile(icon: "bolt.fill", title: String(localized: "Consumption"), value: Fmt.consumption(drive.consumptionNet), tint: .green)
                        StatTile(icon: "battery.75percent", title: String(localized: "Battery"), value: batteryText, tint: .green)
                        StatTile(icon: "thermometer.medium", title: String(localized: "Outside temp"), value: Fmt.temp(drive.outsideTempAvg), tint: .teal)
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
        .navigationTitle(drive.map { Fmt.day($0.startDate) } ?? String(localized: "Drive"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: scrubDate) { _, new in
            if new != nil { heldDate = new }
        }
    }

    private var batteryText: String {
        guard let batt = drive?.batteryDetails, let s = batt.startBatteryLevel, let e = batt.endBatteryLevel else { return "–" }
        return "\(s) → \(e) %"
    }

    private func load() async {
        do {
            drive = try await api.drive(carID: carID, driveID: driveID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SpeedChart: View {
    let points: [DrivePoint]
    @Binding var selection: Date?
    var display: Date?

    // flera punkter kan dela tidsstämpel (sekundupplösning) — AreaMark staplar då y-värden
    private var series: [(date: Date, speed: Double)] {
        var byDate: [Date: Double] = [:]
        for p in points {
            guard let d = p.date, let s = p.speed else { continue }
            byDate[d] = max(byDate[d] ?? 0, s)
        }
        return byDate.keys.sorted().map { (date: $0, speed: byDate[$0]!) }
    }

    private var selectedPoint: DrivePoint? {
        guard let target = selection ?? display else { return nil }
        return points
            .filter { $0.date != nil }
            .min { abs($0.date!.timeIntervalSince(target)) < abs($1.date!.timeIntervalSince(target)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Speed")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let p = selectedPoint {
                    Text(scrubLabel(p))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.blue)
                } else {
                    Text("Drag the chart to follow the drive")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Chart(series, id: \.date) { point in
                AreaMark(x: .value("Time", point.date), y: .value("km/h", point.speed))
                    .foregroundStyle(.blue.opacity(0.15).gradient)
                LineMark(x: .value("Time", point.date), y: .value("km/h", point.speed))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                if let sel = selectedPoint?.date {
                    RuleMark(x: .value("Selected", sel))
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

    private func scrubLabel(_ p: DrivePoint) -> String {
        var parts = [Fmt.time(p.date)]
        if let speed = p.speed { parts.append("\(Int(speed)) km/h") }
        if let power = p.power { parts.append("\(Int(power)) kW") }
        if let level = p.batteryLevel { parts.append("\(level) %") }
        return parts.joined(separator: " · ")
    }
}
