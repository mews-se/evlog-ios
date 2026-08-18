import SwiftUI
import MapKit

struct VisitedView: View {
    let carID: Int
    var current: CLLocationCoordinate2D?

    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value

    // kameran sätts redan i init så vyn öppnar på bilen i stället för att
    // först autozooma ut över alla spår
    init(carID: Int, current: CLLocationCoordinate2D? = nil) {
        self.carID = carID
        self.current = current
        _camera = State(initialValue: current.map {
            .region(MKCoordinateRegion(center: $0, latitudinalMeters: 2000, longitudinalMeters: 2000))
        } ?? .automatic)
    }

    enum Period: String, CaseIterable, Identifiable {
        case off
        case days90
        case year
        case all

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .off: return "Off"
            case .days90: return "90 days"
            case .year: return "This year"
            case .all: return "All"
            }
        }

        var condition: String {
            switch self {
            case .off: return "false"
            case .days90: return "date > now() - interval '90 days'"
            case .year: return "date >= date_trunc('year', now())"
            case .all: return "true"
            }
        }

        var sampleSeconds: Int {
            switch self {
            case .off: return 1
            case .days90: return 20
            case .year: return 45
            case .all: return 90
            }
        }
    }

    @State private var camera: MapCameraPosition
    @State private var period: Period = .off
    @State private var segments: [[CLLocationCoordinate2D]] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
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
    }

    private func load() async {
        // spåren är avstängda som standard - kartan ska visa var bilen ÄR
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
            // ett periodbyte avbröt anropet - efterträdaren äger tillståndet
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            segments = []
            self.error = String(localized: "Couldn't load tracks from Grafana (\(grafanaURL)).")
        }
        loading = false
    }

    // ramar in alla punkter med lite luft, så hela perioden syns när den valts
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

    // bryt polylinen vid tidsgap så det inte dras streck mellan separata körningar
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
