import SwiftUI

struct StatsView: View {
    let api: APIClient
    let carID: Int
    @Binding var path: NavigationPath

    @AppStorage(Pref.tessieToken.key) private var tessieToken = Pref.tessieToken.value
    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value

    enum Granularity: String, CaseIterable, Identifiable {
        case week, month, year

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .week: return "Week"
            case .month: return "Month"
            case .year: return "Year"
            }
        }

        var component: Calendar.Component {
            switch self {
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            }
        }

        // what tapping a row breaks the period down into
        var finer: Calendar.Component {
            switch self {
            case .year: return .month
            case .month, .week: return .day
            }
        }
    }

    @State private var granularity: Granularity = .month
    @State private var drives: [Drive] = []
    @State private var charges: [Charge] = []
    @State private var tessieCosts: [Int: Double] = [:]
    @State private var heaterDrives: Set<Int> = []
    @State private var heaterCharges: Set<Int> = []
    @State private var error: String?
    @State private var partialFailure = false
    @State private var loadedKey: String?

    // changing server, car or Tessie key in settings should invalidate the tab's
    // cache — a newly entered key otherwise stayed hidden until a pull to refresh
    private var loadKey: String { "\(api.baseURL)|\(carID)|\(tessieToken)" }

    private var buckets: [StatBucket] {
        StatBucket.build(drives: drives, charges: charges, tessieCosts: tessieCosts, component: granularity.component)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !drives.isEmpty || !charges.isEmpty {
                    List {
                        if partialFailure {
                            Section {
                                Text("Some of the data could not be loaded.")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                        if !charges.isEmpty {
                            Section {
                                NavigationLink(value: StatsRoute.charging) {
                                    Label("Charging statistics", systemImage: "bolt.badge.clock")
                                }
                            }
                        }
                        Section {
                            Picker("Period", selection: $granularity) {
                                ForEach(Granularity.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                        Section {
                            ForEach(buckets) { bucket in
                                NavigationLink(value: StatsRoute.period(bucket.period, granularity)) {
                                    StatBucketRow(bucket: bucket, component: granularity.component)
                                }
                            }
                        }
                    }
                } else if let error {
                    ErrorCard(message: error) { Task { await load() } }
                } else if loadedKey != nil {
                    ContentUnavailableView("No drives yet", systemImage: "chart.bar")
                } else {
                    ProgressView()
                }
            }
            .navigationDestination(for: StatsRoute.self) { route in
                switch route {
                case let .period(period, granularity):
                    PeriodDetailView(period: period, granularity: granularity,
                                     drives: drives, charges: charges, tessieCosts: tessieCosts)
                case let .day(day):
                    DayDrivesView(day: day, drives: drives, heaterDrives: heaterDrives)
                case .charging:
                    ChargingStatsView(charges: charges, tessieCosts: tessieCosts)
                case let .place(name):
                    PlaceChargesView(name: name, charges: charges, drives: drives,
                                     tessieCosts: tessieCosts, heaterCharges: heaterCharges)
                }
            }
            .navigationDestination(for: DetailRoute.self) { route in
                DetailPager(api: api, carID: carID, route: route, tessieCosts: tessieCosts)
            }
            .navigationTitle("Statistics")
            .refreshable { await load() }
            .task(id: loadKey) { if loadedKey != loadKey { await load() } }
        }
    }

    private func load() async {
        // an error in one fetch should not silently zero the other's columns
        async let d = api.drives(carID: carID)
        async let c = api.charges(carID: carID)
        async let h = GrafanaClient(baseURL: grafanaURL).heaterDrives(carID: carID)
        async let hc = GrafanaClient(baseURL: grafanaURL).heaterCharges(carID: carID)
        var failure: String?
        heaterDrives = (try? await h) ?? []
        heaterCharges = (try? await hc) ?? []
        do { drives = try await d } catch { failure = error.localizedDescription }
        do { charges = try await c } catch { failure = failure ?? error.localizedDescription }
        if drives.isEmpty && charges.isEmpty {
            error = failure
            partialFailure = false
        } else {
            error = nil
            partialFailure = failure != nil
        }
        loadedKey = loadKey
        tessieCosts = await TessieCosts.load(api: api, carID: carID, token: tessieToken, for: charges)
    }
}

struct StatBucket: Identifiable {
    let period: Date
    var distance = 0.0
    var driveMinutes = 0.0
    var driveCount = 0
    var energyConsumed = 0.0
    var rangeDiff = 0.0
    var energyAdded = 0.0
    var cost = 0.0
    var chargeCount = 0

    var id: Date { period }

    // aggregated the way TeslaMate does it: total distance over total range lost
    var efficiencyPct: Double? {
        distance > 0 && rangeDiff > 0 ? distance / rangeDiff * 100 : nil
    }

    // shared by the tab and the period detail view - interval narrows it to one period
    static func build(drives: [Drive], charges: [Charge], tessieCosts: [Int: Double],
                      component: Calendar.Component, within interval: DateInterval? = nil) -> [StatBucket] {
        let calendar = Calendar.current
        var byPeriod: [Date: StatBucket] = [:]

        func key(_ date: Date) -> Date? {
            if let interval, !interval.contains(date) { return nil }
            return calendar.dateInterval(of: component, for: date)?.start ?? date
        }

        for drive in drives {
            guard let k = key(drive.startDate) else { continue }
            var b = byPeriod[k] ?? StatBucket(period: k)
            b.distance += drive.distance
            b.driveMinutes += drive.durationMin ?? 0
            b.driveCount += 1
            b.energyConsumed += drive.energyConsumedNet ?? 0
            b.rangeDiff += drive.rangeRated?.rangeDiff ?? 0
            byPeriod[k] = b
        }
        for charge in charges {
            guard let k = key(charge.startDate) else { continue }
            var b = byPeriod[k] ?? StatBucket(period: k)
            b.energyAdded += charge.chargeEnergyAdded ?? 0
            b.cost += charge.displayCost ?? tessieCosts[charge.chargeId] ?? 0
            b.chargeCount += 1
            byPeriod[k] = b
        }
        return byPeriod.values.sorted { $0.period > $1.period }
    }
}

enum PeriodTitle {
    static func text(_ date: Date, _ component: Calendar.Component) -> String {
        switch component {
        case .weekOfYear:
            let week = Calendar.current.component(.weekOfYear, from: date)
            let year = Calendar.current.component(.yearForWeekOfYear, from: date)
            return String(localized: "Week") + " \(week), \(year)"
        case .month:
            return date.formatted(.dateTime.month(.wide).year().locale(.app)).capitalized
        case .year:
            return date.formatted(.dateTime.year())
        default:
            return Fmt.day(date)
        }
    }
}

struct StatBucketRow: View {
    let bucket: StatBucket
    let component: Calendar.Component

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: PeriodTitle.text(bucket.period, component))
                .font(.subheadline.weight(.semibold))
            HStack {
                item(Fmt.distance(bucket.distance, decimals: 0), .blue)
                item(Fmt.kwh(bucket.energyAdded), .green)
                item(bucket.cost > 0 ? Fmt.kr(bucket.cost) : "–", .primary)
            }
            HStack(spacing: 10) {
                Label { Text(verbatim: "\(bucket.driveCount)") } icon: { Image(systemName: "road.lanes") }
                Label { Text(verbatim: "\(bucket.chargeCount)") } icon: { Image(systemName: "bolt") }
                Label(Fmt.duration(bucket.driveMinutes), systemImage: "clock")
                if let efficiency = bucket.efficiencyPct {
                    Label(Fmt.pct(efficiency, decimals: 0), systemImage: "leaf")
                        .foregroundStyle(CarState.efficiencyColor(efficiency))
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            // the chevron in the list eats width - the row should shrink, not wrap
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 4)
    }

    private func item(_ value: String, _ tint: Color) -> some View {
        Text(verbatim: value)
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PeriodDetailView: View {
    let period: Date
    let granularity: StatsView.Granularity
    let drives: [Drive]
    let charges: [Charge]
    let tessieCosts: [Int: Double]

    private var interval: DateInterval? {
        Calendar.current.dateInterval(of: granularity.component, for: period)
    }

    private var buckets: [StatBucket] {
        StatBucket.build(drives: drives, charges: charges, tessieCosts: tessieCosts,
                         component: granularity.finer, within: interval)
    }

    private var total: StatBucket {
        var t = StatBucket(period: period)
        for b in buckets {
            t.distance += b.distance
            t.driveMinutes += b.driveMinutes
            t.driveCount += b.driveCount
            t.energyConsumed += b.energyConsumed
            t.rangeDiff += b.rangeDiff
            t.energyAdded += b.energyAdded
            t.cost += b.cost
            t.chargeCount += b.chargeCount
        }
        return t
    }

    var body: some View {
        List {
            Section {
                StatBucketRow(bucket: total, component: granularity.component)
            } header: {
                Text("Total")
            }
            Section {
                ForEach(buckets) { bucket in
                    if granularity.finer == .day {
                        NavigationLink(value: StatsRoute.day(bucket.period)) {
                            StatBucketRow(bucket: bucket, component: granularity.finer)
                        }
                    } else {
                        StatBucketRow(bucket: bucket, component: granularity.finer)
                    }
                }
            } header: {
                granularity.finer == .month ? Text("By month") : Text("By day")
            }
        }
        .navigationTitle(PeriodTitle.text(period, granularity.component))
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }
}


// a day row in a month leads here: that day's drives, the same row as in Drives
struct DayDrivesView: View {
    let day: Date
    let drives: [Drive]
    var heaterDrives: Set<Int> = []

    private var ofDay: [Drive] {
        drives
            .filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        Group {
            if ofDay.isEmpty {
                ContentUnavailableView("No drives this day", systemImage: "road.lanes")
            } else {
                let run = ofDay.map { DetailTarget.drive(id: $0.driveId, day: $0.startDate) }
                List {
                    ForEach(Array(ofDay.enumerated()), id: \.element.id) { i, drive in
                        NavigationLink(value: DetailRoute(targets: run, index: i)) {
                            DriveRow(drive: drive, heaterUsed: heaterDrives.contains(drive.driveId))
                        }
                    }
                }
            }
        }
        .navigationTitle(Fmt.day(day))
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }
}
