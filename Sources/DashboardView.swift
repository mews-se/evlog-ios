import SwiftUI
import MapKit

struct DashboardView: View {
    let api: APIClient
    let carID: Int
    @Binding var path: NavigationPath

    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value
    @AppStorage(Pref.tessieToken.key) private var tessieToken = Pref.tessieToken.value

    @State private var showSpec = false
    @State private var status: CarStatus?
    @State private var error: String?
    // whether the last refresh reached the server - the cards keep the last answer
    // either way, so this is the only place a lost connection shows
    @State private var reachable = true
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
                // the name opens the spec sheet - the chevron is the only hint it is a button
                if let name = status?.displayName {
                    ToolbarItem(placement: .principal) {
                        Button {
                            showSpec = true
                        } label: {
                            HStack(spacing: 4) {
                                // the warning colour keeps canned data from passing as a car
                                Text(verbatim: name)
                                    .font(.headline)
                                    .foregroundStyle(api.demo ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                // the antenna is about the server, the rest of the icons about the car
                if !reachable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .accessibilityLabel(Text("No connection to the server"))
                    }
                } else if let state = status?.state {
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
            .sheet(isPresented: $showSpec) {
                CarSpecView(api: api, carID: carID, status: status,
                            marketingName: marketingName, token: tessieToken)
            }
        }
    }

    private func load() async {
        do {
            status = try await api.status(carID: carID)
            error = nil
            reachable = true
        } catch {
            reachable = false
            if status == nil { self.error = error.localizedDescription }
        }
        // additive, never blocking - falls back on the trim code if Grafana is out of reach
        let grafana = GrafanaClient(baseURL: grafanaURL)
        // the queries run in parallel - otherwise the view opens before the answers land
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

    private var showsCable: Bool {
        let state = status.chargingDetails?.chargingState?.lowercased() ?? ""
        return ["charging", "starting", "complete", "stopped", "nopower"].contains(state)
            || status.chargingDetails?.pluggedIn == true
    }

    private var styledCableLine: some View {
        cableLine
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
    }

    @ViewBuilder private func glyphRow(_ glyphs: [(icon: String, color: Color, label: String)]) -> some View {
        if !glyphs.isEmpty {
            HStack(spacing: 8) {
                ForEach(glyphs, id: \.icon) { glyph in
                    if glyph.icon == "fan.fill" {
                        // the page's one moving part: the blades turn while preconditioning runs
                        Image(systemName: glyph.icon)
                            .symbolEffect(.rotate, options: .repeat(.continuous))
                            .foregroundStyle(glyph.color)
                            .accessibilityLabel(Text(verbatim: glyph.label))
                    } else {
                        Image(systemName: glyph.icon)
                            .foregroundStyle(glyph.color)
                            .accessibilityLabel(Text(verbatim: glyph.label))
                    }
                }
            }
            .font(.footnote.weight(.semibold))
        }
    }

    // the state name decides which line shows, not the percentage. teslamateapi
    // lowercases the states on their way through
    @ViewBuilder private var cableLine: some View {
        let charging = status.chargingDetails
        switch charging?.chargingState?.lowercased() {
        case "charging":
            let added = Fmt.kwh(charging?.chargeEnergyAdded)
            let power = charging?.chargerPower.map { Int($0) } ?? 0
            if let hours = charging?.timeToFullCharge, hours > 0 {
                Label("\(added) added · \(power) kW · \(Fmt.duration(hours * 60)) left", systemImage: "bolt.fill")
                    .foregroundStyle(.green)
            } else {
                Label("\(added) added · \(power) kW", systemImage: "bolt.fill")
                    .foregroundStyle(.green)
            }
        case "starting":
            Label("Starting to charge", systemImage: "bolt.fill")
                .foregroundStyle(.green)
        case "complete":
            Label("Charge complete · \(Fmt.pct((charging?.chargeLimitSoc ?? level).map(Double.init), decimals: 0))", systemImage: "bolt.badge.checkmark")
                .foregroundStyle(.green)
        case "stopped":
            if let start = charging?.scheduledStart {
                Label("Plugged in · starts at \(Fmt.time(start))", systemImage: "bolt.badge.clock")
                    .foregroundStyle(.secondary)
            } else {
                Label("Charging stopped · \(Fmt.pct(level.map(Double.init), decimals: 0))", systemImage: "bolt.slash")
                    .foregroundStyle(.secondary)
            }
        case "nopower":
            Label("Plugged in · no power", systemImage: "powerplug.fill")
                .foregroundStyle(.orange)
        default:
            if charging?.pluggedIn == true {
                Label("Plugged in", systemImage: "powerplug.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // TeslaMate's own icon row, with its conditions: off simply does not appear.
    // service mode is missing from the status feed, the map marker's job belongs
    // to the location card, and the lock and sentry cards already say their piece
    private var glyphs: [(icon: String, color: Color, label: String)] {
        var row: [(icon: String, color: Color, label: String)] = []
        let flags = status.carStatus
        let climate = status.climateDetails
        if climate?.isPreconditioning == true {
            row.append(("fan.fill", .secondary, String(localized: "Preconditioning")))
        }
        if climate?.climateKeeperMode == "dog" {
            row.append(("dog.fill", .secondary, String(localized: "Dog Mode")))
        }
        if let full = status.batteryDetails?.batteryLevel,
           let usable = status.batteryDetails?.usableBatteryLevel, full - usable > 2 {
            row.append(("snowflake", .cyan, String(localized: "Reduced battery range")))
        }
        if status.state != "driving", flags?.isUserPresent == true {
            row.append(("person.fill", .secondary, String(localized: "Driver present")))
        }
        if status.chargingDetails?.pluggedIn == true {
            row.append(("powerplug.fill", .secondary, String(localized: "Plugged in")))
        }
        if flags?.windowsOpen == true {
            row.append(("window.vertical.open", .secondary, String(localized: "Windows open")))
        }
        if flags?.doorsOpen == true {
            row.append(("car.top.door.front.left.open", .secondary, String(localized: "Doors open")))
        }
        if status.carVersions?.updateAvailable == true {
            row.append(("gift.fill", .secondary, String(localized: "Software update available")))
        }
        if status.tpmsDetails?.anyWarning == true {
            row.append(("tirepressure", .orange, String(localized: "Low tyre pressure")))
        }
        if flags?.healthy == false {
            row.append(("exclamationmark.square.fill", .red, String(localized: "Health check failed")))
        }
        return row
    }

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
                    Text(verbatim: level.map { "\($0)%" } ?? "–")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    if let range = status.batteryDetails?.ratedBatteryRange {
                        Text(verbatim: Fmt.distance(range, decimals: 0))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 132, height: 132)
            .padding(.top, 2)

            if let projected = status.batteryDetails?.projectedRatedRange {
                Text("≈ \(Fmt.distance(projected, decimals: 0)) at \(Fmt.pct(100, decimals: 0))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let glyphs = self.glyphs
            if showsCable || !glyphs.isEmpty {
                // beside each other when the line is short, stacked when it is not
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        styledCableLine
                        glyphRow(glyphs)
                    }
                    VStack(spacing: 8) {
                        styledCableLine
                        glyphRow(glyphs)
                    }
                }
            }

            HStack {
                Label("Estimated range", systemImage: "map")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                if let model = status.carDetails?.model {
                    // the same line TeslaMate's web UI shows: model + marketing_name
                    Text(verbatim: "Model \(model)" + (marketingName.map { " \($0)" }
                        ?? (status.carDetails?.trimBadging.map { " \($0.uppercased())" } ?? "")))
                }
                Spacer()
                if let odo = status.odometer {
                    Text(verbatim: Fmt.distance(odo, decimals: 0))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct StatusGrid: View {
    let status: CarStatus
    var health: BatteryHealth?
    var countries: [CountryStat] = []

    // the last finished drive is where the car is now
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
                    value: (status.carGeodata?.geofence).flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Unknown"),
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
            // the dot Tesla's own UI uses: filled and red on watch, dotted at rest
            StatTile(
                icon: status.carStatus?.sentryMode == true ? "circle.inset.filled" : "circle.dotted",
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
            Text(verbatim: title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
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

// energy and regen are read against each other, so they share a tile rather than standing apart
struct SplitStatTile: View {
    struct Half {
        let icon: String
        let title: String
        let value: String
        let tint: Color
    }

    let leading: Half
    let trailing: Half

    var body: some View {
        HStack(spacing: 12) {
            half(leading)
            Divider()
            half(trailing)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func half(_ side: Half) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: side.icon)
                .font(.body)
                .foregroundStyle(side.tint)
            Text(verbatim: side.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: side.value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
