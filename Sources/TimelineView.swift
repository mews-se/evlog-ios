import SwiftUI

// drives and charges come from the same API but in separate lists. here they sit in
// one flow per day, where parking is the gap between two entries rather than
// something with a source of its own. the segment picks whether the flow shows
// everything or only one of the kinds
struct TimelineView: View {
    let api: APIClient
    let carID: Int
    @Binding var path: NavigationPath

    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value
    @AppStorage(Pref.tessieToken.key) private var tessieToken = Pref.tessieToken.value

    @State private var filter = TimelineFilter.all
    @State private var drives: [Drive] = []
    @State private var charges: [Charge] = []
    @State private var chargeGroups: [ChargeGroup] = []
    @State private var efficiency: Double?
    @State private var days: [TimelineDay] = []
    @State private var heaterDrives: Set<Int> = []
    @State private var coldCharges: Set<Int>?
    @State private var tessieCosts: [Int: Double] = [:]
    @State private var error: String?
    @State private var loadedKey: String?

    private var loadKey: String { "\(api.baseURL)|\(carID)|\(tessieToken)" }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !days.isEmpty {
                    List {
                        if filter == .charges {
                            Section {
                                YearSummaryCard(groups: chargeGroups, tessieCosts: tessieCosts)
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
                    }
                    .navigationDestination(for: TimelineRoute.self) { route in
                        switch route {
                        case .drive(let id):
                            DriveDetailView(api: api, carID: carID, driveID: id)
                        case .charge(let ids):
                            ChargeDetailView(api: api, carID: carID, chargeIDs: ids, tessieCosts: tessieCosts)
                        }
                    }
                } else if let error {
                    ErrorCard(message: error) { Task { await load() } }
                } else if loadedKey != nil {
                    ContentUnavailableView("No activity yet", systemImage: "calendar.day.timeline.left")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            // the segment sits in the navigation bar rather than above the list:
            // a row inserted there takes space from the flow and kills the large title
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(String(localized: "Timeline", bundle: .current), selection: $filter) {
                        ForEach(TimelineFilter.allCases, id: \.self) { Text($0.title) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    // the navigation bar gives the segment exactly its content width, which
                    // leaves the Swedish "Laddningar" pressed against the edges of its third.
                    // the ceiling is the narrowest phone running iOS 17, 375 points less the
                    // bar's margins
                    .frame(minWidth: 330)
                }
            }
            .refreshable { await load() }
            .task(id: loadKey) { if loadedKey != loadKey { await load() } }
            .onChange(of: filter) { _, _ in rebuild() }
        }
    }

    @ViewBuilder
    private func row(_ entry: TimelineEntry) -> some View {
        switch entry {
        case .drive(let drive):
            NavigationLink(value: TimelineRoute.drive(drive.driveId)) {
                Spine(tint: .blue, symbol: "car.circle.fill") {
                    DriveRow(drive: drive, heaterUsed: heaterDrives.contains(drive.driveId))
                }
            }
        case .charge(let group):
            NavigationLink(value: TimelineRoute.charge(group.parts.map(\.chargeId))) {
                Spine(tint: group.isDC ? .red : .green, symbol: "bolt.circle.fill") {
                    ChargeRow(group: group, tessieCosts: tessieCosts, showsDay: false)
                }
            }
        case .park(let park):
            Spine(tint: .secondary, symbol: "parkingsign.circle.fill") {
                ParkRow(park: park)
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
    }

    private func load() async {
        // the heater query runs in parallel - otherwise the symbol turns up long after the list
        async let heaters = GrafanaClient(baseURL: grafanaURL).heaterDrives(carID: carID)
        async let colds = GrafanaClient(baseURL: grafanaURL).coldChargeStarts(carID: carID)
        do {
            async let loadedDrives = api.drives(carID: carID, results: 500)
            async let loadedCharges = api.charges(carID: carID, results: 500)
            // the park rows turn range loss into kWh through the car's efficiency constant
            async let loadedCars = api.cars()
            (drives, charges) = try await (loadedDrives, loadedCharges)
            efficiency = (try? await loadedCars)?.first { $0.carId == carID }?.carDetails?.efficiency
            rebuild()
            error = nil
        } catch {
            if days.isEmpty { self.error = error.localizedDescription }
        }
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

    var id: String {
        switch self {
        case .drive(let drive): return "drive-\(drive.driveId)"
        case .charge(let group): return "charge-\(group.id)"
        case .park(let park): return "park-\(Int(park.start.timeIntervalSince1970))"
        }
    }

    var isDrive: Bool {
        if case .drive = self { return true }
        return false
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
        }
    }

    // a park belongs to the day it ends. in descending order that puts it directly
    // under the drive it came before instead of at the top of an earlier day
    var day: Date {
        if case .park(let park) = self {
            return Calendar.current.startOfDay(for: park.end)
        }
        return Calendar.current.startOfDay(for: start)
    }

    var end: Date? {
        switch self {
        case .drive(let drive): return drive.endDate
        case .charge(let group): return group.endDate
        case .park(let park): return park.end
        }
    }

    var place: String? {
        switch self {
        case .drive(let drive): return drive.endAddress
        case .charge(let group): return group.address
        case .park(let park): return park.place
        }
    }

    var startLevel: Int? {
        switch self {
        case .drive(let drive): return drive.batteryDetails?.startBatteryLevel
        case .charge(let group): return group.first.batteryDetails?.startBatteryLevel
        case .park(let park): return park.from
        }
    }

    var endLevel: Int? {
        switch self {
        case .drive(let drive): return drive.batteryDetails?.endBatteryLevel
        case .charge(let group): return group.last.batteryDetails?.endBatteryLevel
        case .park(let park): return park.to
        }
    }

    var startRange: Double? {
        switch self {
        case .drive(let drive): return drive.rangeRated?.startRange
        case .charge(let group): return group.first.rangeRated?.startRange
        case .park: return nil
        }
    }

    var endRange: Double? {
        switch self {
        case .drive(let drive): return drive.rangeRated?.endRange
        case .charge(let group): return group.last.rangeRated?.endRange
        case .park: return nil
        }
    }

    var startOdometer: Double? {
        switch self {
        case .drive(let drive): return drive.odometerDetails?.odometerStart
        case .charge(let group): return group.first.odometer
        case .park: return nil
        }
    }

    var endOdometer: Double? {
        switch self {
        case .drive(let drive): return drive.odometerDetails?.odometerEnd
        case .charge(let group): return group.last.odometer
        case .park: return nil
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
}

enum Timeline {
    // shorter stops are loading and unloading, not parking
    static let parkThreshold: TimeInterval = 30 * 60

    static func build(drives: [Drive], chargeGroups: [ChargeGroup],
                      efficiency: Double? = nil, coldCharges: Set<Int>? = nil) -> [TimelineDay] {
        let cutoff = cutoff(drives: drives, chargeGroups: chargeGroups)
        let events = (drives.map(TimelineEntry.drive) + chargeGroups.map(TimelineEntry.charge))
            .filter { $0.start >= cutoff }
            .sorted { $0.start < $1.start }

        var all = events
        for (before, after) in zip(events, events.dropFirst()) {
            guard let from = before.end, after.start.timeIntervalSince(from) >= parkThreshold else { continue }
            all.append(.park(Park(start: from, end: after.start, place: before.place,
                                  from: before.endLevel, to: after.startLevel,
                                  rangeDiff: gapRangeDiff(before: before, after: after, coldCharges: coldCharges),
                                  efficiency: efficiency)))
        }
        return group(all)
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
        case .park:
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

    // the lists reach different distances back. past the shorter one a gap would read
    // as parking when it is really missing data. this holds for the merged flow only —
    // a single segment can show its whole list
    private static func cutoff(drives: [Drive], chargeGroups: [ChargeGroup]) -> Date {
        let oldest = [drives.map(\.startDate).min(), chargeGroups.map(\.startDate).min()].compactMap { $0 }
        return oldest.max() ?? .distantPast
    }
}

enum TimelineRoute: Hashable {
    case drive(Int)
    case charge([Int])
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
                Text(place)
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

// the day heading carries the count of each kind, a summary without anything having
// to be added up
struct DayHeader: View {
    let day: TimelineDay

    var body: some View {
        HStack(spacing: 10) {
            Text(Fmt.day(day.date))
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
