import SwiftUI

struct StatsView: View {
    let api: APIClient
    let carID: Int
    @Binding var path: NavigationPath

    @AppStorage(Pref.tessieToken.key) private var tessieToken = Pref.tessieToken.value
    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value

    enum Granularity: String, CaseIterable, Identifiable {
        case week, month, year, custom

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .week: return "Week"
            case .month: return "Month"
            case .year: return "Year"
            case .custom: return "Custom"
            }
        }

        // a picked span is summed as a whole and has no calendar unit to step by
        var component: Calendar.Component {
            switch self {
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            case .custom: return .day
            }
        }

        // what tapping a row breaks the period down into
        var finer: Calendar.Component {
            switch self {
            case .year: return .month
            case .month, .week, .custom: return .day
            }
        }
    }

    @State private var granularity: Granularity = .month
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -6,
                                                          to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var customTo = Date.now
    @State private var drives: [Drive] = []
    @State private var charges: [Charge] = []
    @State private var tessieCosts: [Int: Double] = [:]
    @State private var heaterDrives: Set<Int> = []
    @State private var heaterCharges: Set<Int> = []
    @State private var stillPlugged: Set<Int> = []
    @State private var error: String?
    @State private var partialFailure = false
    @State private var loadedKey: String?

    // changing server, car or Tessie key in settings should invalidate the tab's
    // cache — a newly entered key otherwise stayed hidden until a pull to refresh
    private var loadKey: String { "\(api.baseURL)|\(carID)|\(tessieToken)" }

    private var buckets: [StatBucket] {
        StatBucket.build(drives: drives, charges: charges, tessieCosts: tessieCosts, stillPlugged: stillPlugged,
                         component: granularity.component)
    }

    // whole days: from the start of the first to midnight after the last
    private var customSpan: DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: customFrom)
        let last = calendar.startOfDay(for: customTo)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: last) ?? last)
    }

    private var customTotal: StatBucket {
        let days = StatBucket.build(drives: drives, charges: charges, tessieCosts: tessieCosts,
                                    stillPlugged: stillPlugged, component: .day, within: customSpan)
        return StatBucket.sum(days, period: customSpan.start)
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
                        Section {
                            if !charges.isEmpty {
                                NavigationLink(value: StatsRoute.charging) {
                                    Label("Charging statistics", systemImage: "bolt.badge.clock")
                                }
                            }
                            if !drives.isEmpty {
                                NavigationLink(value: StatsRoute.destinations) {
                                    Label("Destinations", systemImage: "mappin.and.ellipse")
                                }
                                NavigationLink(value: StatsRoute.temperature) {
                                    Label("Temperature and consumption", systemImage: "thermometer.medium")
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
                        if granularity == .custom {
                            Section {
                                DatePicker("From", selection: $customFrom, in: ...customTo, displayedComponents: .date)
                                DatePicker("To", selection: $customTo, in: customFrom...Date.now, displayedComponents: .date)
                            }
                            Section {
                                NavigationLink(value: StatsRoute.span(customSpan.start, customSpan.end)) {
                                    StatBucketRow(bucket: customTotal, title: PeriodTitle.span(customSpan))
                                }
                            }
                        } else {
                            Section {
                                ForEach(buckets) { bucket in
                                    NavigationLink(value: StatsRoute.period(bucket.period, granularity)) {
                                        StatBucketRow(bucket: bucket, component: granularity.component)
                                    }
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
                                     drives: drives, charges: charges, tessieCosts: tessieCosts,
                                     stillPlugged: stillPlugged)
                case let .span(start, end):
                    PeriodDetailView(span: DateInterval(start: start, end: end),
                                     drives: drives, charges: charges, tessieCosts: tessieCosts,
                                     stillPlugged: stillPlugged)
                case let .day(day):
                    DayDrivesView(day: day, drives: drives, heaterDrives: heaterDrives)
                case .charging:
                    ChargingStatsView(charges: charges, drives: drives, tessieCosts: tessieCosts,
                                      stillPlugged: stillPlugged)
                case .temperature:
                    TempConsumptionView(drives: drives)
                case .destinations:
                    DestinationsView(drives: drives, heaterDrives: heaterDrives)
                case let .destination(name):
                    PlaceDrivesView(name: name, drives: drives, heaterDrives: heaterDrives)
                case let .place(name):
                    PlaceChargesView(name: name, charges: charges, drives: drives,
                                     tessieCosts: tessieCosts, heaterCharges: heaterCharges,
                                     stillPlugged: stillPlugged)
                }
            }
            .navigationDestination(for: DetailRoute.self) { route in
                DetailPager(api: api, carID: carID, route: route, tessieCosts: tessieCosts)
            }
            .navigationTitle("Statistics")
            .refreshable {
                ServerCheck.shared.forget()
                await load()
            }
            .task(id: loadKey) { if loadedKey != loadKey { await load() } }
        }
    }

    private func load() async {
        // an error in one fetch should not silently zero the other's columns
        async let d = api.drives(carID: carID)
        async let c = api.charges(carID: carID)
        async let h = GrafanaClient(baseURL: grafanaURL).heaterDrives(carID: carID)
        async let hc = GrafanaClient(baseURL: grafanaURL).heaterCharges(carID: carID)
        async let p = GrafanaClient(baseURL: grafanaURL).stillPluggedCharges(carID: carID)
        var failure: String?
        heaterDrives = (try? await h) ?? []
        heaterCharges = (try? await hc) ?? []
        stillPlugged = (try? await p) ?? []
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
    // range lost times the car's efficiency, per drive. teslamateapi leaves it null
    // where no range was lost, so nil here means no drive had anything to add
    var energyConsumed: Double?
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
    static func build(drives: [Drive], charges: [Charge], tessieCosts: [Int: Double], stillPlugged: Set<Int> = [],
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
            if let energy = drive.energyConsumedNet { b.energyConsumed = (b.energyConsumed ?? 0) + energy }
            b.rangeDiff += drive.rangeRated?.rangeDiff ?? 0
            byPeriod[k] = b
        }
        // joined the way the timeline joins them, so an evening on the cable counts once
        // and lands on the day it started
        for group in ChargeGroup.stitch(charges, drives: drives, stillPlugged: stillPlugged) {
            guard let k = key(group.startDate) else { continue }
            var b = byPeriod[k] ?? StatBucket(period: k)
            b.energyAdded += group.energyAdded ?? 0
            b.cost += group.cost(tessieCosts: tessieCosts) ?? 0
            b.chargeCount += 1
            byPeriod[k] = b
        }
        return byPeriod.values.sorted { $0.period > $1.period }
    }

    static func sum(_ buckets: [StatBucket], period: Date) -> StatBucket {
        var t = StatBucket(period: period)
        for b in buckets {
            t.distance += b.distance
            t.driveMinutes += b.driveMinutes
            t.driveCount += b.driveCount
            if let energy = b.energyConsumed { t.energyConsumed = (t.energyConsumed ?? 0) + energy }
            t.rangeDiff += b.rangeDiff
            t.energyAdded += b.energyAdded
            t.cost += b.cost
            t.chargeCount += b.chargeCount
        }
        return t
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

    // a span ends at midnight after its last day, which is the day the title names
    static func span(_ interval: DateInterval) -> String {
        let last = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return (interval.start..<max(interval.start, last)).formatted(.interval.day().month().year().locale(.app))
    }
}

struct StatBucketRow: View {
    let bucket: StatBucket
    let title: String

    init(bucket: StatBucket, title: String) {
        self.bucket = bucket
        self.title = title
    }

    init(bucket: StatBucket, component: Calendar.Component) {
        self.init(bucket: bucket, title: PeriodTitle.text(bucket.period, component))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
            // the driving first, the charging last. charged kWh beside the distance
            // read as what the drives had used
            HStack {
                item(Fmt.distance(bucket.distance, decimals: 0), .blue)
                item(Fmt.kwh(bucket.energyConsumed), .purple)
                item(Fmt.pct(bucket.efficiencyPct, decimals: 0), CarState.efficiencyColor(bucket.efficiencyPct))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Label { Text(verbatim: "\(bucket.driveCount)") } icon: { Image(systemName: "road.lanes") }
                    Label(Fmt.duration(bucket.driveMinutes), systemImage: "clock")
                }
                // a line of its own: a year of charges with energy and cost does not
                // fit beside the driving time
                Label { Text(verbatim: charging) } icon: { Image(systemName: "bolt") }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            // the chevron in the list eats width - the row should shrink, not wrap
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 4)
    }

    private var charging: String {
        guard bucket.chargeCount > 0 else { return "0" }
        var parts = ["\(bucket.chargeCount)", Fmt.kwh(bucket.energyAdded)]
        if bucket.cost > 0 { parts.append(Fmt.cost(bucket.cost)) }
        return parts.joined(separator: " · ")
    }

    private func item(_ value: String, _ tint: Color) -> some View {
        Text(verbatim: value)
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PeriodDetailView: View {
    let interval: DateInterval?
    let title: String
    // what the period breaks down into
    let finer: Calendar.Component
    let drives: [Drive]
    let charges: [Charge]
    let tessieCosts: [Int: Double]
    var stillPlugged: Set<Int> = []
    // the calendar unit the period is one of, nil for a picked span
    var unit: Calendar.Component?

    private var buckets: [StatBucket] {
        StatBucket.build(drives: drives, charges: charges, tessieCosts: tessieCosts, stillPlugged: stillPlugged,
                         component: finer, within: interval)
    }

    private var total: StatBucket {
        StatBucket.sum(buckets, period: interval?.start ?? .now)
    }

    private var comparison: PeriodComparison? {
        guard let interval else { return nil }
        return PeriodComparison(interval: interval, unit: unit, drives: drives, charges: charges,
                                tessieCosts: tessieCosts, stillPlugged: stillPlugged)
    }

    var body: some View {
        List {
            Section {
                StatBucketRow(bucket: total, title: title)
            } header: {
                Text("Total")
            }
            if let comparison {
                Section {
                    Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Color.clear
                                .gridCellUnsizedAxes([.horizontal, .vertical])
                            ForEach(comparison.columns) { column in
                                Text(verbatim: column.title)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        change(String(localized: "Distance"), comparison) { $0.distance }
                        change(String(localized: "Energy"), comparison) { $0.energyConsumed }
                    }
                } header: {
                    Text("Compared with")
                } footer: {
                    if let days = comparison.daysSoFar {
                        days == 1
                            ? Text("The period is still running, so each is compared over its first day.")
                            : Text("The period is still running, so each is compared over its first \(days) days.")
                    }
                }
            }
            Section {
                ForEach(buckets) { bucket in
                    if finer == .day {
                        NavigationLink(value: StatsRoute.day(bucket.period)) {
                            StatBucketRow(bucket: bucket, component: finer)
                        }
                    } else {
                        StatBucketRow(bucket: bucket, component: finer)
                    }
                }
            } header: {
                finer == .month ? Text("By month") : Text("By day")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }

    private func change(_ label: String, _ comparison: PeriodComparison,
                        _ value: @escaping (StatBucket) -> Double?) -> some View {
        GridRow {
            Text(verbatim: label)
                .gridColumnAlignment(.leading)
            ForEach(comparison.columns) { column in
                Text(verbatim: PeriodComparison.change(value(total), value(column.bucket)))
                    .monospacedDigit()
            }
        }
    }
}

extension PeriodDetailView {
    init(period: Date, granularity: StatsView.Granularity,
         drives: [Drive], charges: [Charge], tessieCosts: [Int: Double], stillPlugged: Set<Int>) {
        self.init(interval: Calendar.current.dateInterval(of: granularity.component, for: period),
                  title: PeriodTitle.text(period, granularity.component), finer: granularity.finer,
                  drives: drives, charges: charges, tessieCosts: tessieCosts, stillPlugged: stillPlugged,
                  unit: granularity.component)
    }

    // a picked span longer than two months reads better by month than as a wall of days
    init(span: DateInterval, drives: [Drive], charges: [Charge], tessieCosts: [Int: Double],
         stillPlugged: Set<Int>) {
        let twoMonths = Calendar.current.date(byAdding: .month, value: 2, to: span.start) ?? span.end
        self.init(interval: span, title: PeriodTitle.span(span), finer: span.end > twoMonths ? .month : .day,
                  drives: drives, charges: charges, tessieCosts: tessieCosts, stillPlugged: stillPlugged)
    }
}

// a period against the one before it and the same one a year earlier. one still
// running is held against the same stretch of the others, or half a month would
// always read as a quiet one
struct PeriodComparison {
    struct Column: Identifiable {
        let title: String
        let bucket: StatBucket
        var id: String { title }
    }

    let columns: [Column]
    // days gone of a period still running, nil once it is over
    let daysSoFar: Int?

    init?(interval: DateInterval, unit: Calendar.Component?, drives: [Drive], charges: [Charge],
          tessieCosts: [Int: Double], stillPlugged: Set<Int>, now: Date = .now) {
        let calendar = Calendar.current
        guard let first = (drives.map(\.startDate) + charges.map(\.startDate)).min() else { return nil }
        // a period the log only partly covers would show a rise that is just the log starting
        let logStart = calendar.startOfDay(for: first)
        let elapsed = interval.end > now
            ? calendar.dateComponents([.day, .hour, .minute, .second], from: interval.start, to: now)
            : nil

        func column(_ span: DateInterval, _ title: String) -> Column? {
            guard span.start >= logStart else { return nil }
            var end = span.end
            if let elapsed, let cut = calendar.date(byAdding: elapsed, to: span.start) { end = min(end, cut) }
            let days = StatBucket.build(drives: drives, charges: charges, tessieCosts: tessieCosts,
                                        stillPlugged: stillPlugged, component: .day,
                                        within: DateInterval(start: span.start, end: end))
            return Column(title: title, bucket: StatBucket.sum(days, period: span.start))
        }

        var columns: [Column?] = []
        if let unit {
            if let start = calendar.date(byAdding: unit, value: -1, to: interval.start) {
                columns.append(column(DateInterval(start: start, end: interval.start), PeriodTitle.text(start, unit)))
            }
            // the year before is the one before. elsewhere the middle of the period finds
            // the same week a year back, where its first day would land a week early
            let middle = interval.start.addingTimeInterval(interval.duration / 2)
            if unit != .year, let then = calendar.date(byAdding: .year, value: -1, to: middle),
               let back = calendar.dateInterval(of: unit, for: then) {
                columns.append(column(back, PeriodTitle.text(back.start, unit)))
            }
        } else {
            let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
            if let start = calendar.date(byAdding: .day, value: -days, to: interval.start) {
                let before = DateInterval(start: start, end: interval.start)
                columns.append(column(before, PeriodTitle.span(before)))
            }
            if let start = calendar.date(byAdding: .year, value: -1, to: interval.start),
               let end = calendar.date(byAdding: .year, value: -1, to: interval.end), start < end {
                let back = DateInterval(start: start, end: end)
                columns.append(column(back, PeriodTitle.span(back)))
            }
        }
        self.columns = columns.compactMap { $0 }
        guard !self.columns.isEmpty else { return nil }
        daysSoFar = elapsed.map { _ in
            (calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: now)).day ?? 0) + 1
        }
    }

    static func change(_ now: Double?, _ then: Double?) -> String {
        guard let now, let then, then > 0 else { return "–" }
        let pct = ((now / then - 1) * 100).rounded()
        if pct == 0 { return "0 %" }
        return pct.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always())) + " %"
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
