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

        // vad ett klick på en rad bryter ner perioden i
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
    @State private var error: String?
    @State private var partialFailure = false
    @State private var loadedKey: String?

    // server-, bil- eller tessiebyte i inställningarna ska ogiltigförklara flikens
    // cache — en nyinlagd nyckel syntes annars inte förrän man drog för att uppdatera
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
                }
            }
            .navigationDestination(for: Int.self) { driveID in
                DriveDetailView(api: api, carID: carID, driveID: driveID)
            }
            .navigationTitle("Statistics")
            .refreshable { await load() }
            .task(id: loadKey) { if loadedKey != loadKey { await load() } }
        }
    }

    private func load() async {
        // ett fel i den ena hämtningen ska inte tyst nolla den andras kolumner
        async let d = api.allDrives(carID: carID)
        async let c = api.charges(carID: carID, results: 5000)
        async let h = GrafanaClient(baseURL: grafanaURL).heaterDrives(carID: carID)
        var failure: String?
        heaterDrives = (try? await h) ?? []
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

    // aggregerad på samma sätt som TeslaMate: summa sträcka delat med summa räckviddstapp
    var efficiencyPct: Double? {
        distance > 0 && rangeDiff > 0 ? distance / rangeDiff * 100 : nil
    }

    // delas av fliken och periodens detaljvy - interval avgränsar till en vald period
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
            return date.formatted(.dateTime.month(.wide).year()).capitalized
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
            Text(PeriodTitle.text(bucket.period, component))
                .font(.subheadline.weight(.semibold))
            HStack {
                item(Fmt.km(bucket.distance, decimals: 0), .blue)
                item(Fmt.kwh(bucket.energyAdded), .green)
                item(bucket.cost > 0 ? Fmt.kr(bucket.cost) : "–", .primary)
            }
            HStack(spacing: 10) {
                Label("\(bucket.driveCount)", systemImage: "road.lanes")
                Label("\(bucket.chargeCount)", systemImage: "bolt")
                Label(Fmt.duration(bucket.driveMinutes), systemImage: "clock")
                if let efficiency = bucket.efficiencyPct {
                    Label(Fmt.pct(efficiency, decimals: 0), systemImage: "leaf")
                        .foregroundStyle(CarState.efficiencyColor(efficiency))
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            // chevronen i listan äter bredd - raden ska krympa, inte radbrytas
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 4)
    }

    private func item(_ value: String, _ tint: Color) -> some View {
        Text(value)
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
                Text(granularity.finer == .month ? "By month" : "By day")
            }
        }
        .navigationTitle(PeriodTitle.text(period, granularity.component))
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }
}


// dagsraden i en månad leder hit: resorna den dagen, samma rad som i Drives
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
                List {
                    ForEach(ofDay) { drive in
                        NavigationLink(value: drive.driveId) {
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
