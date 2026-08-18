import SwiftUI
import MapKit

struct RangeMapView: View {
    let center: CLLocationCoordinate2D
    let rangeKm: Double
    // hur många vägkilometer som går åt per kilometer fågelvägen, ur egna resor
    var detour: Double

    @State private var camera: MapCameraPosition
    @State private var chargers: [Supercharger] = []

    init(center: CLLocationCoordinate2D, rangeKm: Double, detour: Double) {
        self.center = center
        self.rangeKm = rangeKm
        self.detour = detour
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: rangeKm * 2600,
            longitudinalMeters: rangeKm * 2600
        )))
    }

    private var realistic: Double { rangeKm / max(detour, 1) }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                MapCircle(center: center, radius: rangeKm * 1000)
                    .foregroundStyle(.clear)
                    .stroke(.green.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                MapCircle(center: center, radius: realistic * 1000)
                    .foregroundStyle(.green.opacity(0.20))
                    .stroke(.green, lineWidth: 2)
                ForEach(chargers) { charger in
                    // egen annotation i stället för Marker: ballongen går inte att krympa
                    Annotation(charger.name, coordinate: charger.coordinate) {
                        ZStack {
                            Circle().fill(within(charger) ? .red : .secondary)
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 14, height: 14)
                        .shadow(radius: 1)
                    }
                    .annotationTitles(.hidden)
                }
                Annotation("", coordinate: center) {
                    ZStack {
                        Circle().fill(.white)
                        Circle().fill(.blue).padding(3)
                    }
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    legend(color: .green, filled: true,
                           title: String(localized: "Realistic reach"), value: Fmt.km(realistic, decimals: 0))
                    legend(color: .green.opacity(0.45), filled: false,
                           title: String(localized: "Straight line"), value: Fmt.km(rangeKm, decimals: 0))
                }
                if !chargers.isEmpty {
                    Text("\(chargers.filter(within).count) of \(chargers.count) Superchargers are within realistic reach. \(SuperchargeClient.attribution)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Roads are not straight. Your own drives cover \(Fmt.number(detour)) km of road per kilometre in a straight line, so the filled circle is the honest one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .navigationTitle("Range")
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
        .task {
            // cachen visas direkt, nätfrågan får komma när den kommer
            let key = ChargerCache.key(center, rangeKm)
            let cached = ChargerCache.load(key)
            if let cached { chargers = cached.chargers }
            guard cached == nil || cached?.stale == true else { return }
            if let fresh = try? await SuperchargeClient().sites(around: center, radiusKm: rangeKm),
               !fresh.isEmpty {
                chargers = fresh
                ChargerCache.save(fresh, key)
            }
        }
    }

    // avstånd fågelvägen mot den realistiska ringen
    private func within(_ charger: Supercharger) -> Bool {
        CLLocation(latitude: charger.coordinate.latitude, longitude: charger.coordinate.longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) <= realistic * 1000
    }

    private func legend(color: Color, filled: Bool, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(filled ? color.opacity(0.25) : .clear)
                .overlay(Circle().stroke(color, style: StrokeStyle(lineWidth: 2, dash: filled ? [] : [3, 2])))
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.callout.weight(.semibold).monospacedDigit())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
