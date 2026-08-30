import SwiftUI
import MapKit

struct VisitedView: View {
    let carID: Int
    var current: CLLocationCoordinate2D?

    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value
    @AppStorage(Pref.visitedMapStyle.key) private var mapStyleKey = Pref.visitedMapStyle.value

    // the camera is set in init so the view opens on the car instead of first
    // auto-zooming out across every track
    init(carID: Int, current: CLLocationCoordinate2D? = nil) {
        self.carID = carID
        self.current = current
        _camera = State(initialValue: current.map {
            .region(MKCoordinateRegion(center: $0, latitudinalMeters: 2000, longitudinalMeters: 2000))
        } ?? .automatic)
    }

    enum Period: Hashable {
        case off
        case days(Int)
        case year
        case all
        case custom(from: Date, to: Date)

        static let quickPicks: [Period] = [.off, .days(7), .days(30), .days(90), .year, .all]

        var title: Text {
            switch self {
            case .off: return Text("Off")
            case .days(7): return Text("7 days")
            case .days(30): return Text("30 days")
            case .days(90): return Text("90 days")
            case .days(let n): return Text(verbatim: "\(n) days")
            case .year: return Text("This year")
            case .all: return Text("All")
            case .custom(let from, let to):
                return Text(verbatim: "\(Fmt.shortDate(from)) – \(Fmt.shortDate(to))")
            }
        }

        var condition: String {
            switch self {
            case .off: return "false"
            case .days(let n): return "date > now() - interval '\(n) days'"
            case .year: return "date >= date_trunc('year', now())"
            case .all: return "true"
            case .custom(let from, let to):
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: from)
                let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to)) ?? to
                return "date >= '\(Self.sqlDate(start))' and date < '\(Self.sqlDate(end))'"
            }
        }

        // the sampling follows the window instead of sitting fixed per preset, so a
        // week keeps its corners while everything keeps its point count. 90 days at
        // 20 seconds is the budget the old presets were tuned to.
        var sampleSeconds: Int {
            let days: Double
            switch self {
            case .off: return 1
            case .all: return 90
            case .days(let n): days = Double(n)
            case .year:
                let start = Calendar.current.dateInterval(of: .year, for: .now)?.start ?? .now
                days = Date.now.timeIntervalSince(start) / 86_400
            case .custom(let from, let to):
                let calendar = Calendar.current
                days = calendar.startOfDay(for: to).timeIntervalSince(calendar.startOfDay(for: from)) / 86_400 + 1
            }
            return max(1, min(90, Int(days / 4.5)))
        }

        // positions store naive UTC timestamps
        private static func sqlDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: date)
        }
    }

    enum MapStylePick: String {
        case standard, satellite
    }

    @State private var camera: MapCameraPosition
    @State private var period: Period = .off
    @State private var showCustomSheet = false
    @State private var segments: [[CLLocationCoordinate2D]] = []
    @State private var loading = false
    @State private var error: String?

    private var mapStyle: MapStylePick { MapStylePick(rawValue: mapStyleKey) ?? .standard }

    private var isCustom: Bool {
        if case .custom = period { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                periodMenu
                Spacer()
                mapStyleButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ZStack {
                Map(position: $camera) {
                    ForEach(segments.indices, id: \.self) { i in
                        MapPolyline(coordinates: segments[i])
                            .stroke(.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                    if let current {
                        Annotation("", coordinate: current) {
                            ZStack {
                                Circle().fill(.white)
                                Circle().fill(.blue).padding(3)
                            }
                            .frame(width: 22, height: 22)
                            .shadow(radius: 2)
                        }
                    }
                }
                // hybrid rather than plain imagery - the labels are what say where you are
                .mapStyle(mapStyle == .satellite ? .hybrid : .standard)
                if loading {
                    ProgressView("Loading tracks…")
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else if let error {
                    ErrorCard(message: error) { Task { await load() } }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                }
            }
        }
        .navigationTitle("Visited")
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
        .task(id: period) { await load() }
        .sheet(isPresented: $showCustomSheet) {
            let now = Calendar.current.startOfDay(for: .now)
            let (from, to): (Date, Date) = {
                if case .custom(let f, let t) = period { return (f, t) }
                return (Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now, now)
            }()
            CustomPeriodSheet(from: from, to: to) { period = .custom(from: $0, to: $1) }
                .presentationDetents([.medium])
        }
    }

    private var periodMenu: some View {
        Menu {
            ForEach(Period.quickPicks, id: \.self) { pick in
                Toggle(isOn: Binding(get: { period == pick }, set: { if $0 { period = pick } })) {
                    pick.title
                }
            }
            Divider()
            // the toggle look keeps the checkmark honest, but tapping it always
            // opens the sheet - an active range is adjusted, not switched off
            Toggle(isOn: Binding(get: { isCustom }, set: { _ in showCustomSheet = true })) {
                Text("Custom range…")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                period.title
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.subheadline.weight(.medium))
        }
    }

    private var mapStyleButton: some View {
        Button {
            mapStyleKey = (mapStyle == .satellite ? MapStylePick.standard : .satellite).rawValue
        } label: {
            Image(systemName: mapStyle == .satellite ? "map" : "globe.americas")
                .font(.subheadline.weight(.medium))
        }
        .accessibilityLabel(Text("Map style"))
    }

    private func load() async {
        // the tracks are off by default - the map should show where the car IS
        guard period != .off else {
            segments = []
            error = nil
            loading = false
            if let current {
                camera = .region(MKCoordinateRegion(center: current, latitudinalMeters: 2000, longitudinalMeters: 2000))
            }
            return
        }
        loading = true
        error = nil
        do {
            let points = try await GrafanaClient(baseURL: grafanaURL)
                .positions(carID: carID, condition: period.condition, sampleSeconds: period.sampleSeconds)
            segments = Self.splitIntoSegments(points)
            if let region = Self.boundingRegion(points) { camera = .region(region) }
            if points.isEmpty { error = String(localized: "No tracks in this period.") }
        } catch is CancellationError {
            // a period change cancelled the call - the successor owns the state
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            segments = []
            self.error = String(localized: "Couldn't load tracks from Grafana (\(grafanaURL)).")
        }
        loading = false
    }

    // frames every point with a little air, so the whole period shows once picked
    static func boundingRegion(_ points: [TrackPoint]) -> MKCoordinateRegion? {
        guard let first = points.first else { return nil }
        var minLat = first.lat, maxLat = first.lat
        var minLon = first.lon, maxLon = first.lon
        for p in points {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.25, 0.02),
                longitudeDelta: max((maxLon - minLon) * 1.25, 0.02)
            )
        )
    }

    // break the polyline at time gaps so no line is drawn between separate drives
    static func splitIntoSegments(_ points: [TrackPoint]) -> [[CLLocationCoordinate2D]] {
        var out: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        var last: TrackPoint?
        for p in points {
            if let l = last, p.date.timeIntervalSince(l.date) > 600 {
                if current.count > 1 { out.append(current) }
                current = []
            }
            current.append(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon))
            last = p
        }
        if current.count > 1 { out.append(current) }
        return out
    }
}

struct CustomPeriodSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var from: Date
    @State var to: Date
    let apply: (Date, Date) -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                DatePicker("To", selection: $to, in: from...Date.now, displayedComponents: .date)
            }
            .navigationTitle("Custom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") { apply(from, to); dismiss() }
                }
            }
        }
    }
}
