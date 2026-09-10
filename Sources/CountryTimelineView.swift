import SwiftUI

// a country row leads here: the drives that ended there and the charges there, in the
// timeline's own rows. parking is left out - between two entries in one country the car
// may well have been in another
struct CountryTimelineView: View {
    let api: APIClient
    let carID: Int
    let country: CountryStat

    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value
    @AppStorage(Pref.tessieToken.key) private var tessieToken = Pref.tessieToken.value

    @State private var days: [TimelineDay] = []
    @State private var targets: [DetailTarget] = []
    @State private var targetIndex: [String: Int] = [:]
    @State private var heaterDrives: Set<Int> = []
    @State private var heaterCharges: Set<Int> = []
    @State private var tessieCosts: [Int: Double] = [:]
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Group {
            if !days.isEmpty {
                List {
                    ForEach(days) { day in
                        Section {
                            ForEach(day.entries) { entry in
                                row(entry)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 12))
                                    .listRowSeparator(.hidden)
                            }
                        } header: {
                            DayHeader(day: day)
                        }
                    }
                    Section {} footer: {
                        Text("Drives that started or ended in the country, and the charges there.")
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
                .navigationDestination(for: DetailRoute.self) { route in
                    DetailPager(api: api, carID: carID, route: route, tessieCosts: tessieCosts)
                }
            } else if let error {
                ErrorCard(message: error) { Task { await load() } }
            } else if loaded {
                ContentUnavailableView("Nothing here yet", systemImage: "globe")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text(verbatim: "\(country.flag) \(country.displayName)"))
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
        .task { await load() }
    }

    @ViewBuilder
    private func row(_ entry: TimelineEntry) -> some View {
        switch entry {
        case .drive(let drive):
            NavigationLink(value: DetailRoute(targets: targets, index: targetIndex[entry.id] ?? 0)) {
                Spine(tint: .blue, symbol: "car.circle.fill") {
                    DriveRow(drive: drive, heaterUsed: heaterDrives.contains(drive.driveId))
                }
            }
        case .charge(let group):
            NavigationLink(value: DetailRoute(targets: targets, index: targetIndex[entry.id] ?? 0)) {
                Spine(tint: group.isDC ? .red : .green, symbol: "bolt.circle.fill") {
                    ChargeRow(group: group, tessieCosts: tessieCosts,
                              heaterUsed: group.parts.contains { heaterCharges.contains($0.chargeId) })
                }
            }
        case .park, .missing, .update:
            EmptyView()
        }
    }

    private func load() async {
        let grafana = GrafanaClient(baseURL: grafanaURL)
        async let heaters = grafana.heaterDrives(carID: carID)
        async let heatedCharges = grafana.heaterCharges(carID: carID)
        do {
            async let ids = grafana.countryIDs(carID: carID, code: country.code)
            async let drives = api.drives(carID: carID)
            async let charges = api.charges(carID: carID)
            let (here, allDrives, allCharges) = try await (ids, drives, charges)
            let drivesHere = allDrives.filter { here.drives.contains($0.driveId) }
            // joined the way the timeline joins, then kept when the stretch is in the country
            let groups = ChargeGroup.stitch(allCharges, drives: allDrives)
                .filter { group in group.parts.contains { here.charges.contains($0.chargeId) } }
            days = Timeline.group(drivesHere.map(TimelineEntry.drive) + groups.map(TimelineEntry.charge))
            var run: [DetailTarget] = []
            var at: [String: Int] = [:]
            for entry in days.flatMap(\.entries) {
                guard let target = entry.target else { continue }
                at[entry.id] = run.count
                run.append(target)
            }
            targets = run
            targetIndex = at
            error = nil
            loaded = true
            tessieCosts = await TessieCosts.load(api: api, carID: carID, token: tessieToken,
                                                 for: groups.flatMap(\.parts))
        } catch {
            if days.isEmpty { self.error = error.localizedDescription }
            loaded = true
        }
        heaterDrives = (try? await heaters) ?? []
        heaterCharges = (try? await heatedCharges) ?? []
    }
}
