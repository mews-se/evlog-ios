import SwiftUI
import MapKit

struct DashboardView: View {
    let api: APIClient
    let carID: Int
    @Binding var path: NavigationPath

    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value

    @State private var status: CarStatus?
    @State private var error: String?
    @State private var marketingName: String?
    @State private var batteryHealth: BatteryHealth?
    @State private var countries: [CountryStat] = []
    @State private var detour: Double?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if let status {
                    VStack(spacing: 12) {
                        NavigationLink(value: OverviewRoute.range(
                            lat: status.carGeodata?.latitude,
                            lon: status.carGeodata?.longitude,
                            km: status.batteryDetails?.ratedBatteryRange
                        )) {
                            BatteryCard(status: status, marketingName: marketingName)
                        }
                        .buttonStyle(.plain)
                        StatusGrid(status: status, health: batteryHealth, countries: countries)
                        if status.carVersions?.updateAvailable == true {
                            UpdateBanner(version: status.carVersions?.updateVersion)
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
            .navigationDestination(for: OverviewRoute.self) { route in
                switch route {
                case let .visited(lat, lon):
                    VisitedView(carID: carID, current: lat.flatMap { la in
                        lon.map { CLLocationCoordinate2D(latitude: la, longitude: $0) }
                    })
                case let .software(version):
                    SoftwareView(api: api, carID: carID, current: version)
                case .batteryHealth:
                    BatteryHealthView(health: batteryHealth)
                case .countries:
                    CountriesView(countries: countries)
                case let .range(lat, lon, km):
                    if let lat, let lon, let km, km > 0 {
                        RangeMapView(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                     rangeKm: km, detour: detour ?? 1.4)
                    } else {
                        ContentUnavailableView("No position yet", systemImage: "map")
                    }
                }
            }
            .navigationTitle(status?.displayName ?? String(localized: "Overview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let state = status?.state {
                    let s = CarState.label(state, charging: status?.chargingDetails?.chargingState)
                    ToolbarItem(placement: .topBarTrailing) {
                        Image(systemName: s.icon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(s.color)
                            .accessibilityLabel(Text(verbatim: s.text))
                    }
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            status = try await api.status(carID: carID)
            error = nil
        } catch {
            if status == nil { self.error = error.localizedDescription }
        }
        // tillägg, aldrig blockerande - faller tillbaka på trim-koden om Grafana inte nås
        let grafana = GrafanaClient(baseURL: grafanaURL)
        // frågorna går parallellt - annars hinner vyn öppnas innan svaren kommer
        async let name = grafana.marketingName(carID: carID)
        async let health = grafana.batteryHealth(carID: carID)
        async let lands = grafana.countries(carID: carID)
        async let factor = grafana.detourFactor(carID: carID)
        if marketingName == nil { marketingName = try? await name }
        if batteryHealth == nil { batteryHealth = try? await health }
        if countries.isEmpty { countries = (try? await lands) ?? [] }
        if detour == nil { detour = try? await factor }
    }
}

struct BatteryCard: View {
    let status: CarStatus
    var marketingName: String?

    private var level: Int? { status.batteryDetails?.usableBatteryLevel ?? status.batteryDetails?.batteryLevel }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: CGFloat(level ?? 0) / 100)
                    .stroke(
                        CarState.batteryColor(level).gradient,
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(level.map { "\($0)%" } ?? "–")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    if let range = status.batteryDetails?.ratedBatteryRange {
                        Text(Fmt.km(range, decimals: 0))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 132, height: 132)
            .padding(.top, 2)

            if let projected = status.batteryDetails?.projectedRatedRange {
                Text("≈ \(Fmt.km(projected, decimals: 0)) at \(Fmt.pct(100, decimals: 0))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if status.chargingDetails?.chargingState == "Charging" {
                let power = status.chargingDetails?.chargerPower
                let added = status.chargingDetails?.chargeEnergyAdded
                Label("\(Fmt.kwh(added)) added · \(power.map { Int($0) } ?? 0) kW", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            } else if status.chargingDetails?.pluggedIn == true {
                Label("Plugged in", systemImage: "powerplug.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Range on this charge", systemImage: "map")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                if let model = status.carDetails?.model {
                    // samma rad som TeslaMates webb: modell + marketing_name
                    Text(verbatim: "Model \(model)" + (marketingName.map { " \($0)" }
                        ?? (status.carDetails?.trimBadging.map { " \($0.uppercased())" } ?? "")))
                }
                Spacer()
                if let odo = status.odometer {
                    Text(Fmt.km(odo, decimals: 0))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

// platshållare tills vi bestämt vad de två knapparna ska göra
struct StatusGrid: View {
    let status: CarStatus
    var health: BatteryHealth?
    var countries: [CountryStat] = []

    // senast avslutade resan avgör var bilen är nu
    private var current: CountryStat? {
        countries.max { ($0.lastVisit ?? .distantPast) < ($1.lastVisit ?? .distantPast) }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            StatTile(
                icon: status.carStatus?.locked == true ? "lock.fill" : "lock.open.fill",
                title: String(localized: "Lock"),
                value: status.carStatus?.locked == true ? String(localized: "Locked") : String(localized: "Unlocked"),
                tint: status.carStatus?.locked == true ? .green : .orange
            )
            NavigationLink(value: OverviewRoute.visited(lat: status.carGeodata?.latitude,
                                                        lon: status.carGeodata?.longitude)) {
                StatTile(
                    icon: "mappin.and.ellipse",
                    title: String(localized: "Location"),
                    value: status.carGeodata?.geofence?.isEmpty == false ? status.carGeodata!.geofence! : String(localized: "Unknown"),
                    tint: .blue,
                    chevron: true
                )
            }
            .buttonStyle(.plain)
            StatTile(
                icon: "thermometer.medium",
                title: String(localized: "Outside / inside"),
                value: "\(Fmt.temp(status.climateDetails?.outsideTemp)) / \(Fmt.temp(status.climateDetails?.insideTemp))",
                tint: .teal
            )
            StatTile(
                icon: "shield.fill",
                title: "Sentry",
                value: status.carStatus?.sentryMode == true ? String(localized: "On") : String(localized: "Off"),
                tint: status.carStatus?.sentryMode == true ? .red : .secondary
            )
            NavigationLink(value: OverviewRoute.batteryHealth) {
                StatTile(
                    icon: "battery.100percent.bolt",
                    title: String(localized: "Degradation"),
                    value: Fmt.pct(health?.degradation),
                    tint: .teal,
                    chevron: true
                )
            }
            .buttonStyle(.plain)
            .disabled(health == nil)
            NavigationLink(value: OverviewRoute.countries) {
                StatTile(
                    icon: "globe",
                    title: String(localized: "Countries"),
                    value: current.map { "\($0.flag) \($0.displayName)" } ?? "–",
                    tint: .indigo,
                    chevron: true
                )
            }
            .buttonStyle(.plain)
            .disabled(countries.isEmpty)
            NavigationLink(value: OverviewRoute.software(version: status.carVersions?.version)) {
                StatTile(
                    icon: "cpu",
                    title: String(localized: "Software"),
                    value: status.carVersions?.version?.components(separatedBy: " ").first ?? "–",
                    tint: .purple,
                    chevron: true
                )
            }
            .buttonStyle(.plain)
            StatTile(
                icon: "clock.fill",
                title: statusSinceTitle,
                value: Fmt.since(status.stateSince),
                tint: .secondary
            )
        }
    }

    private var statusSinceTitle: String {
        let state = CarState.label(status.state, charging: status.chargingDetails?.chargingState).text
        return String(localized: "\(state) since")
    }
}

struct StatTile: View {
    let icon: String
    let title: String
    let value: String
    var tint: Color = .primary
    var valueTint: Color?
    var chevron: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(tint)
                Spacer()
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(valueTint ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct UpdateBanner: View {
    let version: String?

    var body: some View {
        Group {
            if let version {
                Label("Software Update available (\(version))", systemImage: "arrow.down.circle.fill")
            } else {
                Label("Update available", systemImage: "arrow.down.circle.fill")
            }
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.purple)
    }
}
