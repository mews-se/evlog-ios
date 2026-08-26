import SwiftUI

// drives and charges come from the same API but in separate lists. here they sit in
// one flow per day, where parking is the gap between two entries rather than
// something with a source of its own. the segment picks whether the flow shows
// everything or only one of the kinds, the period how far back it reaches
struct TimelineView: View {
    let api: APIClient
    let carID: Int
    @Binding var path: NavigationPath

    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value
    @AppStorage(Pref.tessieToken.key) private var tessieToken = Pref.tessieToken.value
    @AppStorage(Pref.timelinePeriod.key) private var periodKey = Pref.timelinePeriod.value

    @State private var filter = TimelineFilter.all
    @State private var drives: [Drive] = []
    @State private var charges: [Charge] = []
    @State private var chargeGroups: [ChargeGroup] = []
    @State private var efficiency: Double?
    @State private var days: [TimelineDay] = []
    // the flow as a run of details, and where each row sits in it
    @State private var targets: [DetailTarget] = []
    @State private var targetIndex: [String: Int] = [:]
    @State private var heaterDrives: Set<Int> = []
    @State private var coldCharges: Set<Int>?
    @State private var tessieCosts: [Int: Double] = [:]
    @State private var error: String?
    @State private var loadedKey: String?
    @State private var loading = false

    private var period: TimelinePeriod { TimelinePeriod(rawValue: periodKey) ?? .month }
    private var loadKey: String { "\(api.baseURL)|\(carID)|\(tessieToken)|\(periodKey)" }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !days.isEmpty {
                    List {
                        if filter == .charges {
                            Section {
                                ChargeSummaryCard(title: period.title, groups: chargeGroups, tessieCosts: tessieCosts)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                            }
                        }
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
                        // the flow says where it stops instead of just stopping
                        Section {} footer: {
                            (period == .all ? Text("That is everything TeslaMate has recorded.")
                                            : Text("Older entries are outside the period."))
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .navigationDestination(for: DetailRoute.self) { route in
                        DetailPager(api: api, carID: carID, route: route, tessieCosts: tessieCosts)
                    }
                } else if let error {
                    ErrorCard(message: error) { Task { await load() } }
                } else if loadedKey != nil {
                    if period == .all {
                        ContentUnavailableView("No activity yet", systemImage: "calendar.day.timeline.left")
                    } else {
                        ContentUnavailableView("Nothing in this period", systemImage: "calendar.day.timeline.left",
                                               description: Text("Choose a longer period above."))
                    }
                } else {
                    ProgressView()
                }
            }
            // the period sits above the list rather than in the bar, which the segment
            // already fills on the narrowest phones. it stays put when the list is empty,
            // since that is exactly when it needs changing
            .safeAreaInset(edge: .top, spacing: 0) { periodBar }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            // the segment sits in the navigation bar rather than above the list, where
            // the period row already takes its share of the flow
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(String(localized: "Timeline"), selection: $filter) {
                        ForEach(TimelineFilter.allCases, id: \.self) { Text($0.title) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    // the navigation bar gives the segment exactly its content width, which
                    // presses the longest title against the edges of its third. the ceiling
                    // is the narrowest phone running iOS 17, 375 points less the bar's margins
                    .frame(minWidth: 330)
                }
            }
            .refreshable { await load() }
            .task(id: loadKey) { if loadedKey != loadKey { await load() } }
            .onChange(of: filter) { _, _ in rebuild() }
        }
    }

    private var periodBar: some View {
        HStack {
            Menu {
                Picker(String(localized: "Period"), selection: $periodKey) {
                    ForEach(TimelinePeriod.allCases, id: \.rawValue) { Text($0.title) }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(period.title)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .font(.subheadline.weight(.medium))
            }
            Spacer()
            if loading {
                ProgressView()
                    .controlSize(.small)
            } else if let from = reachesBack {
                Text("From \(Fmt.shortDate(from))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // a bounded period reaches back to its own start; everything reaches to the
    // oldest entry there is, which is only known once it has been loaded
    private var reachesBack: Date? {
        if let start = period.start() { return start }
        return days.last?.entries.last?.start
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
                    ChargeRow(group: group, tessieCosts: tessieCosts)
                }
            }
        case .park(let park):
            Spine(tint: .secondary, symbol: "parkingsign.circle.fill") {
                ParkRow(park: park)
            }
        case .missing(let gap):
            Spine(tint: Color(.tertiaryLabel), symbol: "questionmark.circle.fill") {
                MissingRow(gap: gap)
            }
        }
    }

    private func rebuild() {
        chargeGroups = ChargeGroup.stitch(charges, drives: drives)
        switch filter {
        case .all: days = Timeline.build(drives: drives, chargeGroups: chargeGroups,
                                         efficiency: efficiency, coldCharges: coldCharges)
        case .drives: days = Timeline.group(drives.map(TimelineEntry.drive))
        case .charges: days = Timeline.group(chargeGroups.map(TimelineEntry.charge))
        }
        var run: [DetailTarget] = []
        var at: [String: Int] = [:]
        for entry in days.flatMap(\.entries) {
            guard let target = entry.target else { continue }
            at[entry.id] = run.count
            run.append(target)
        }
        targets = run
        targetIndex = at
    }

    private func load() async {
        let since = period.start()
        loading = true
        // the heater query runs in parallel - otherwise the symbol turns up long after the list
        async let heaters = GrafanaClient(baseURL: grafanaURL).heaterDrives(carID: carID)
        async let colds = GrafanaClient(baseURL: grafanaURL).coldChargeStarts(carID: carID)
        do {
            async let loadedDrives = api.drives(carID: carID, since: since)
            async let loadedCharges = api.charges(carID: carID, since: since)
            // the park rows turn range loss into kWh through the car's efficiency constant
            async let loadedCars = api.cars()
            (drives, charges) = try await (loadedDrives, loadedCharges)
            efficiency = (try? await loadedCars)?.first { $0.carId == carID }?.carDetails?.efficiency
            rebuild()
            error = nil
        } catch {
            // a period picked mid-load cancels this one, and that is not a failure to show
            if Task.isCancelled { return }
            if days.isEmpty { self.error = error.localizedDescription }
        }
        loading = false
        loadedKey = loadKey
        heaterDrives = (try? await heaters) ?? []
        // park figures are baked in at build time, so a late answer needs a rebuild
        if let answered = try? await colds {
            coldCharges = answered
            rebuild()
        }
        // additive, never blocking — fails quietly if Tessie is out of reach
        tessieCosts = await TessieCosts.load(api: api, carID: carID, token: tessieToken, for: charges)
    }
}

enum TimelineFilter: CaseIterable {
    case all, drives, charges

    var title: LocalizedStringKey {
        switch self {
        case .all: return "All"
        case .drives: return "Drives"
        case .charges: return "Charges"
        }
    }
}

enum TimelinePeriod: String, CaseIterable {
    case week, month, year, all

    var title: LocalizedStringKey {
        switch self {
        case .week: return "Last week"
        case .month: return "Last month"
        case .year: return "This year"
        case .all: return "All time"
        }
    }

    // where the flow starts; nil reaches back through everything there is
    func start(now: Date = .now, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -7, to: today)
        case .month: return calendar.date(byAdding: .month, value: -1, to: today)
        case .year: return calendar.dateInterval(of: .year, for: now)?.start
        case .all: return nil
        }
    }
}

struct TimelineDay: Identifiable {
    let date: Date
    let entries: [TimelineEntry]

    var id: Date { date }

    var driveCount: Int { entries.filter(\.isDrive).count }
    var chargeCount: Int { entries.filter(\.isCharge).count }
}

enum TimelineEntry: Identifiable {
    case drive(Drive)
    case charge(ChargeGroup)
    case park(Park)
    case missing(Missing)

    var id: String {
        switch self {
        case .drive(let drive): return "drive-\(drive.driveId)"
        case .charge(let group): return "charge-\(group.id)"
        case .park(let park): return "park-\(Int(park.start.timeIntervalSince1970))"
        case .missing(let gap): return "missing-\(Int(gap.start.timeIntervalSince1970))"
        }
    }

    var isDrive: Bool {
        if case .drive = self { return true }
        return false
    }

    // gaps have no page of their own and are skipped when swiping through the day
    var target: DetailTarget? {
        switch self {
        case .drive(let drive): return .drive(id: drive.driveId, day: drive.startDate)
        case .charge(let group): return .charge(ids: group.parts.map(\.chargeId), address: group.address)
        case .park, .missing: return nil
        }
    }

    var isCharge: Bool {
        if case .charge = self { return true }
        return false
    }

    var start: Date {
        switch self {
        case .drive(let drive): return drive.startDate
        case .charge(let group): return group.startDate
        case .park(let park): return park.start
        case .missing(let gap): return gap.start
        }
    }

    // a gap belongs to the day it ends. in descending order that puts it directly
    // under the drive it came before instead of at the top of an earlier day
    var day: Date {
        switch self {
        case .park(let park): return Calendar.current.startOfDay(for: park.end)
        case .missing(let gap): return Calendar.current.startOfDay(for: gap.end)
        default: return Calendar.current.startOfDay(for: start)
        }
    }

    var end: Date? {
        switch self {
        case .drive(let drive): return drive.endDate
        case .charge(let group): return group.endDate
        case .park(let park): return park.end
        case .missing(let gap): return gap.end
        }
    }

    var place: String? {
        switch self {
        case .drive(let drive): return drive.endAddress
        case .charge(let group): return group.address
        case .park(let park): return park.place
        case .missing(let gap): return gap.to
        }
    }

    var startPlace: String? {
        switch self {
        case .drive(let drive): return drive.startAddress
        case .charge(let group): return group.address
        case .park(let park): return park.place
        case .missing(let gap): return gap.from
        }
    }

    var startLevel: Int? {
        switch self {
        case .drive(let drive): return drive.batteryDetails?.startBatteryLevel
        case .charge(let group): return group.first.batteryDetails?.startBatteryLevel
        case .park(let park): return park.from
        case .missing: return nil
        }
    }

    var endLevel: Int? {
        switch self {
        case .drive(let drive): return drive.batteryDetails?.endBatteryLevel
        case .charge(let group): return group.last.batteryDetails?.endBatteryLevel
        case .park(let park): return park.to
        case .missing: return nil
        }
    }

    var startRange: Double? {
        switch self {
        case .drive(let drive): return drive.rangeRated?.startRange
        case .charge(let group): return group.first.rangeRated?.startRange
        case .park, .missing: return nil
        }
    }

    var endRange: Double? {
        switch self {
        case .drive(let drive): return drive.rangeRated?.endRange
        case .charge(let group): return group.last.rangeRated?.endRange
        case .park, .missing: return nil
        }
    }

    var startOdometer: Double? {
        switch self {
        case .drive(let drive): return drive.odometerDetails?.odometerStart
        case .charge(let group): return group.first.odometer
        case .park, .missing: return nil
        }
    }

    var endOdometer: Double? {
        switch self {
        case .drive(let drive): return drive.odometerDetails?.odometerEnd
        case .charge(let group): return group.last.odometer
        case .park, .missing: return nil
        }
    }

    // a cold pack reports less usable range without any energy having left the battery
    var startsWithReducedRange: Bool {
        if case .drive(let drive) = self,
           let level = drive.batteryDetails?.startBatteryLevel,
           let usable = drive.batteryDetails?.startUsableBatteryLevel {
            return level > usable
        }
        return false
    }
}

struct Park {
    let start: Date
    let end: Date
    let place: String?
    let from: Int?
    let to: Int?
    let rangeDiff: Double?
    let efficiency: Double?

    var minutes: Double { end.timeIntervalSince(start) / 60 }

    // only drops count: a higher level afterwards means a charge TeslaMate did not see
    var drop: Int? {
        guard let from, let to, from > to else { return nil }
        return from - to
    }

    // the Vampire Drain arithmetic: range lost times the car's efficiency constant
    var drainKWh: Double? {
        guard let rangeDiff, let efficiency else { return nil }
        return rangeDiff * efficiency
    }

    // a short stop earns a row by what it cost, not by how long it took. the level is
    // too coarse to notice - range is a hundred times finer and already does the sums
    var costsEnough: Bool {
        (drainKWh ?? 0) >= Timeline.shortStopFloorKWh
    }
}

// a stretch the log does not cover: the car moved, and nothing was recorded while
// it did. TeslaMate's timeline calls this missing, and this is its rule
struct Missing {
    let start: Date
    let end: Date
    let from: String?
    let to: String?
    let km: Double

    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

enum Timeline {
    // shorter stops are loading and unloading, not parking - unless the battery paid
    // for them, which the climate or Sentry can manage in twenty minutes
    static let parkThreshold: TimeInterval = 30 * 60
    // below this a short stop's loss is rounding and the row would be noise
    static let shortStopFloorKWh = 0.05
    // the range readout settles for a few minutes after a drive, and that shows up as
    // kilowatts over a gap of a minute or two. a stop shorter than this is not parking,
    // whatever the figures say
    static let shortStopMinimum: TimeInterval = 5 * 60
    // TeslaMate's bound for an unrecorded drive: the odometer moved this far, and the
    // address changed with it, so a few hundred metres inside one car park stay parking
    static let missingKm = 0.5

    // both lists are complete back to the same point, so a gap between two entries is
    // a gap in the car's day and not one list running out before the other
    static func build(drives: [Drive], chargeGroups: [ChargeGroup],
                      efficiency: Double? = nil, coldCharges: Set<Int>? = nil) -> [TimelineDay] {
        let events = (drives.map(TimelineEntry.drive) + chargeGroups.map(TimelineEntry.charge))
            .sorted { $0.start < $1.start }

        var all = events
        for (before, after) in zip(events, events.dropFirst()) {
            guard let from = before.end else { continue }
            // a parked row makes a claim about the car standing still. if the odometer
            // says otherwise, the gap is a drive nobody logged and gets said as such
            if let moved = movedKm(before: before, after: after) {
                all.append(.missing(Missing(start: from, end: after.start, from: before.place,
                                            to: after.startPlace, km: moved)))
                continue
            }
            let park = Park(start: from, end: after.start, place: before.place,
                            from: before.endLevel, to: after.startLevel,
                            rangeDiff: gapRangeDiff(before: before, after: after, coldCharges: coldCharges),
                            efficiency: efficiency)
            let stood = after.start.timeIntervalSince(from)
            guard stood >= parkThreshold || (stood >= shortStopMinimum && park.costsEnough) else { continue }
            all.append(.park(park))
        }
        return group(all)
    }

    private static func movedKm(before: TimelineEntry, after: TimelineEntry) -> Double? {
        guard let start = before.endOdometer, let end = after.startOdometer,
              end - start > missingKm, before.place != after.startPlace else { return nil }
        return end - start
    }

    // the guards are TeslaMate's own: a cold pack fakes a loss, a moved car means an
    // unrecorded drive ate the range, and a gain means a charge slipped past the log
    private static func gapRangeDiff(before: TimelineEntry, after: TimelineEntry,
                                     coldCharges: Set<Int>?) -> Double? {
        guard let from = before.endRange, let to = after.startRange, to <= from,
              let start = before.endOdometer, let end = after.startOdometer, end - start < 1
        else { return nil }
        switch after {
        case .drive:
            if after.startsWithReducedRange { return nil }
        case .charge(let group):
            // whether the pack was cold is only knowable through Grafana - no answer, no figures
            guard let coldCharges, !coldCharges.contains(group.first.chargeId) else { return nil }
        case .park, .missing:
            return nil
        }
        return from - to
    }

    static func group(_ entries: [TimelineEntry]) -> [TimelineDay] {
        Dictionary(grouping: entries) { $0.day }
            .sorted { $0.key > $1.key }
            .map { day in
                TimelineDay(date: day.key, entries: day.value.sorted { $0.start > $1.start })
            }
    }
}

struct ParkRow: View {
    let park: Park

    var body: some View {
        // the P on the spine says what the row is, so no icon of its own. the colours
        // follow the drive rows - grey on a grey card was not readable. a park is always
        // the day's last row and otherwise sat tight against the card edge
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Parked \(Fmt.duration(park.minutes))")
                    .font(.footnote.weight(.medium))
                Spacer()
                if let figures {
                    Text(verbatim: figures)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let place = park.place {
                Text(verbatim: place)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    // the percentage stays as the fallback: when the range numbers are guarded away
    // the battery drop is still an honest, if crude, figure
    private var figures: String? {
        var parts: [String] = []
        if let drop = park.drop {
            parts.append("−\(drop) %")
        }
        if let drain = park.drainKWh {
            parts.append(Fmt.energy(drain))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct MissingRow: View {
    let gap: Missing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("No data for \(Fmt.duration(gap.minutes))")
                    .font(.footnote.weight(.medium))
                Spacer()
                Text(verbatim: Fmt.distance(gap.km))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let from = gap.from, let to = gap.to {
                Text(verbatim: "\(from) → \(to)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

// the day heading carries the count of each kind, a summary without anything having
// to be added up
struct DayHeader: View {
    let day: TimelineDay

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: Fmt.day(day.date))
            Spacer()
            if day.driveCount > 0 {
                count(day.driveCount, icon: "road.lanes")
            }
            if day.chargeCount > 0 {
                count(day.chargeCount, icon: "bolt.fill")
            }
        }
    }

    private func count(_ value: Int, icon: String) -> some View {
        Label {
            Text(verbatim: "\(value)")
        } icon: {
            Image(systemName: icon)
        }
        .labelStyle(.titleAndIcon)
        .monospacedDigit()
    }
}

// the line with dots to the left of the rows. rows sit edge to edge with no
// separators, so the line runs unbroken through the day and breaks at the next heading
struct Spine<Content: View>: View {
    let tint: Color
    var symbol: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                marker
                    .foregroundStyle(tint)
                    .padding(.top, 16)
            }
            .frame(width: 9)
            content
                .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var marker: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 13))
        } else {
            Circle()
                .frame(width: 9, height: 9)
                .padding(.top, 1)
        }
    }
}

// measures as tinted chips instead of a grey row of icons - quicker to read when
// three numbers stand side by side
struct MetricChip: View {
    var text: String? = nil
    var icon: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            if let text {
                Text(verbatim: text)
            }
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}
