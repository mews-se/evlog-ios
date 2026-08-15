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
                    ContentUnavailableView("Inga resor än", systemImage: "road.lanes")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Resor")
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
                Text("\(Fmt.time(drive.startDate)) – \(Fmt.time(drive.endDate))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Fmt.km(drive.distance))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            Text("\(drive.startAddress ?? "Okänd") → \(drive.endAddress ?? "Okänd")")
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

    private var track: [CLLocationCoordinate2D] {
        (drive?.driveDetails ?? []).compactMap { point in
            guard let lat = point.latitude, let lon = point.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
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
                                Marker("Mål", systemImage: "flag.checkered", coordinate: last).tint(.red)
                            }
                        }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .allowsHitTesting(false)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "Sträcka", value: Fmt.km(drive.distance), tint: .blue)
                        StatTile(icon: "clock.fill", title: "Restid", value: Fmt.duration(drive.durationMin), tint: .secondary)
                        StatTile(icon: "gauge.with.dots.needle.67percent", title: "Max / snitt", value: "\(Int(drive.speedMax ?? 0)) / \(Int(drive.speedAvg ?? 0)) km/h", tint: .orange)
                        StatTile(icon: "bolt.fill", title: "Förbrukning", value: Fmt.consumption(drive.consumptionNet), tint: .green)
                        StatTile(icon: "battery.75percent", title: "Batteri", value: batteryText, tint: .green)
                        StatTile(icon: "thermometer.medium", title: "Utetemp", value: Fmt.temp(drive.outsideTempAvg), tint: .teal)
                    }

                    if let points = drive.driveDetails, points.count > 2 {
                        SpeedChart(points: points)
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
        .navigationTitle(drive.map { Fmt.day($0.startDate) } ?? "Resa")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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

    // flera punkter kan dela tidsstämpel (sekundupplösning) — AreaMark staplar då y-värden
    private var series: [(date: Date, speed: Double)] {
        var byDate: [Date: Double] = [:]
        for p in points {
            guard let d = p.date, let s = p.speed else { continue }
            byDate[d] = max(byDate[d] ?? 0, s)
        }
        return byDate.keys.sorted().map { (date: $0, speed: byDate[$0]!) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hastighet")
                .font(.subheadline.weight(.semibold))
            Chart(series, id: \.date) { point in
                AreaMark(x: .value("Tid", point.date), y: .value("km/h", point.speed))
                    .foregroundStyle(.blue.opacity(0.15).gradient)
                LineMark(x: .value("Tid", point.date), y: .value("km/h", point.speed))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
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
