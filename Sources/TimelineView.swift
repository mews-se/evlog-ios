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
    @State private var days: [TimelineDay] = []
    @State private var heaterDrives: Set<Int> = []
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
                                YearSummaryCard(charges: charges, tessieCosts: tessieCosts)
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
                        case .charge(let id):
                            ChargeDetailView(api: api, carID: carID, chargeID: id, tessieCost: tessieCosts[id])
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
        case .charge(let charge):
            NavigationLink(value: TimelineRoute.charge(charge.chargeId)) {
                Spine(tint: charge.isDC ? .red : .green, symbol: "bolt.circle.fill") {
                    ChargeRow(charge: charge, tessieCost: tessieCosts[charge.chargeId], showsDay: false)
                }
            }
        case .park(let park):
            Spine(tint: .secondary, symbol: "parkingsign.circle.fill") {
                ParkRow(park: park)
            }
        }
    }

    private func rebuild() {
        switch filter {
        case .all: days = Timeline.build(drives: drives, charges: charges)
        case .drives: days = Timeline.group(drives.map(TimelineEntry.drive))
        case .charges: days = Timeline.group(charges.map(TimelineEntry.charge))
        }
    }

    private func load() async {
        // the heater query runs in parallel - otherwise the symbol turns up long after the list
        async let heaters = GrafanaClient(baseURL: grafanaURL).heaterDrives(carID: carID)
        do {
            async let loadedDrives = api.drives(carID: carID, results: 500)
            async let loadedCharges = api.charges(carID: carID, results: 500)
            (drives, charges) = try await (loadedDrives, loadedCharges)
            rebuild()
            error = nil
        } catch {
            if days.isEmpty { self.error = error.localizedDescription }
        }
        loadedKey = loadKey
        heaterDrives = (try? await heaters) ?? []
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
    case charge(Charge)
    case park(Park)

    var id: String {
        switch self {
        case .drive(let drive): return "drive-\(drive.driveId)"
        case .charge(let charge): return "charge-\(charge.chargeId)"
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
        case .charge(let charge): return charge.startDate
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
        case .charge(let charge): return charge.endDate
        case .park(let park): return park.end
        }
    }

    var place: String? {
        switch self {
        case .drive(let drive): return drive.endAddress
        case .charge(let charge): return charge.address
        case .park(let park): return park.place
        }
    }

    var startLevel: Int? {
        switch self {
        case .drive(let drive): return drive.batteryDetails?.startBatteryLevel
        case .charge(let charge): return charge.batteryDetails?.startBatteryLevel
        case .park(let park): return park.from
        }
    }

    var endLevel: Int? {
        switch self {
        case .drive(let drive): return drive.batteryDetails?.endBatteryLevel
        case .charge(let charge): return charge.batteryDetails?.endBatteryLevel
        case .park(let park): return park.to
        }
    }
}

struct Park {
    let start: Date
    let end: Date
    let place: String?
    let from: Int?
    let to: Int?

    var minutes: Double { end.timeIntervalSince(start) / 60 }

    // only drops count: a higher level afterwards means a charge TeslaMate did not see
    var drop: Int? {
        guard let from, let to, from > to else { return nil }
        return from - to
    }
}

enum Timeline {
    // shorter stops are loading and unloading, not parking
    static let parkThreshold: TimeInterval = 30 * 60

    static func build(drives: [Drive], charges: [Charge]) -> [TimelineDay] {
        let cutoff = cutoff(drives: drives, charges: charges)
        let events = (drives.map(TimelineEntry.drive) + charges.map(TimelineEntry.charge))
            .filter { $0.start >= cutoff }
            .sorted { $0.start < $1.start }

        var all = events
        for (before, after) in zip(events, events.dropFirst()) {
            guard let from = before.end, after.start.timeIntervalSince(from) >= parkThreshold else { continue }
            all.append(.park(Park(start: from, end: after.start, place: before.place,
                                  from: before.endLevel, to: after.startLevel)))
        }
        return group(all)
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
    private static func cutoff(drives: [Drive], charges: [Charge]) -> Date {
        let oldest = [drives.map(\.startDate).min(), charges.map(\.startDate).min()].compactMap { $0 }
        return oldest.max() ?? .distantPast
    }
}

enum TimelineRoute: Hashable {
    case drive(Int)
    case charge(Int)
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
                if let drop = park.drop {
                    Text(verbatim: "−\(drop) %")
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
