import SwiftUI
import MapKit

struct VisitedView: View {
    let carID: Int

    @AppStorage("grafanaURL") private var grafanaURL = "http://10.0.0.185:3000"

    enum Period: String, CaseIterable, Identifiable {
        case days90
        case year
        case all

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .days90: return "90 days"
            case .year: return "This year"
            case .all: return "All"
            }
        }

        var condition: String {
            switch self {
            case .days90: return "date > now() - interval '90 days'"
            case .year: return "date >= date_trunc('year', now())"
            case .all: return "true"
            }
        }

        var sampleSeconds: Int {
            switch self {
            case .days90: return 20
            case .year: return 45
            case .all: return 90
            }
        }
    }

    @State private var period: Period = .year
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
                Map {
                    ForEach(segments.indices, id: \.self) { i in
                        MapPolyline(coordinates: segments[i])
                            .stroke(.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
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
        .task(id: period) { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            let points = try await GrafanaClient(baseURL: grafanaURL)
                .positions(carID: carID, condition: period.condition, sampleSeconds: period.sampleSeconds)
            segments = Self.splitIntoSegments(points)
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
