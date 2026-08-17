import SwiftUI

struct DashboardView: View {
    let api: APIClient
    let carID: Int

    @State private var status: CarStatus?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let status {
                    VStack(spacing: 16) {
                        BatteryCard(status: status)
                        StatusGrid(status: status, carID: carID)
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
            .navigationTitle(status?.displayName ?? String(localized: "Overview"))
            .toolbar {
                if let state = status?.state {
                    let s = CarState.label(state, charging: status?.chargingDetails?.chargingState)
                    ToolbarItem(placement: .topBarTrailing) {
                        Label(s.text, systemImage: s.icon)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(s.color)
                            .labelStyle(.titleAndIcon)
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
    }
}

struct BatteryCard: View {
    let status: CarStatus

    private var level: Int? { status.batteryDetails?.usableBatteryLevel ?? status.batteryDetails?.batteryLevel }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: CGFloat(level ?? 0) / 100)
                    .stroke(
                        CarState.batteryColor(level).gradient,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(level.map { "\($0)%" } ?? "–")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    if let range = status.batteryDetails?.ratedBatteryRange {
                        Text(Fmt.km(range, decimals: 0))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 170, height: 170)
            .padding(.top, 8)

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
                if let model = status.carDetails?.model {
                    Text(verbatim: "Model \(model)\(status.carDetails?.trimBadging.map { " \($0.uppercased())" } ?? "")")
                }
                Spacer()
                if let odo = status.odometer {
                    Text(Fmt.km(odo, decimals: 0))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct StatusGrid: View {
    let status: CarStatus
    let carID: Int

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            StatTile(
                icon: status.carStatus?.locked == true ? "lock.fill" : "lock.open.fill",
                title: String(localized: "Lock"),
                value: status.carStatus?.locked == true ? String(localized: "Locked") : String(localized: "Unlocked"),
                tint: status.carStatus?.locked == true ? .green : .orange
            )
            NavigationLink {
                VisitedView(carID: carID)
            } label: {
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
            StatTile(
                icon: "cpu",
                title: String(localized: "Software"),
                value: status.carVersions?.version?.components(separatedBy: " ").first ?? "–",
                tint: .purple
            )
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
