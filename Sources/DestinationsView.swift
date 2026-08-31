import SwiftUI

// the charging places have a ranking; this is the drives' counterpart, built
// from the end addresses the tab already holds
struct DestinationsView: View {
    let drives: [Drive]
    var heaterDrives: Set<Int> = []

    struct Place: Identifiable {
        let name: String
        var count = 0
        var km = 0.0

        var id: String { name }
    }

    private var places: [Place] {
        var byName: [String: Place] = [:]
        for drive in drives {
            let name = drive.endAddress ?? String(localized: "Unknown location")
            var place = byName[name] ?? Place(name: name)
            place.count += 1
            place.km += drive.distance
            byName[name] = place
        }
        return Array(byName.values)
    }

    private var mostVisited: [Place] {
        Array(places.sorted {
            $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count
        }.prefix(10))
    }

    private var mostDistance: [Place] {
        Array(places.filter { $0.km > 0 }.sorted { $0.km > $1.km }.prefix(5))
    }

    // MARK: - Weekdays / weekend

    // the calendar says what a weekend is, so the split follows the region
    private var weekdayDrives: [Drive] { drives.filter { !Calendar.current.isDateInWeekend($0.startDate) } }
    private var weekendDrives: [Drive] { drives.filter { Calendar.current.isDateInWeekend($0.startDate) } }

    private func km(_ list: [Drive]) -> Double { list.reduce(0) { $0 + $1.distance } }
    private func minutes(_ list: [Drive]) -> Double { list.compactMap(\.durationMin).reduce(0, +) }

    // MARK: - Heatmap

    // weekday (0 = Sunday, as Calendar has it) against hour, distance summed
    private var heat: [[Double]] {
        var grid = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        let calendar = Calendar.current
        for drive in drives {
            let weekday = calendar.component(.weekday, from: drive.startDate) - 1
            let hour = calendar.component(.hour, from: drive.startDate)
            grid[weekday][hour] += drive.distance
        }
        return grid
    }

    private var orderedDays: [Int] {
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { (first + $0) % 7 }
    }

    var body: some View {
        List {
            Section {
                ForEach(mostVisited) { place in
                    NavigationLink(value: StatsRoute.destination(place.name)) {
                        PlaceRow(name: place.name, detail: Fmt.distance(place.km, decimals: 0),
                                 value: "\(place.count)", tint: .blue)
                    }
                }
            } header: {
                Text("Most visited")
            }

            if !mostDistance.isEmpty {
                Section {
                    ForEach(mostDistance) { place in
                        NavigationLink(value: StatsRoute.destination(place.name)) {
                            PlaceRow(name: place.name, detail: "\(place.count)",
                                     value: Fmt.distance(place.km, decimals: 0), tint: .blue)
                        }
                    }
                } header: {
                    Text("Most distance")
                }
            }

            Section {
                SplitBar(left: km(weekdayDrives), right: km(weekendDrives),
                         leftLabel: String(localized: "Weekdays"), rightLabel: String(localized: "Weekend"),
                         leftTint: .blue, rightTint: .orange)
                LabeledContent(String(localized: "Distance")) {
                    Text(verbatim: "\(Fmt.distance(km(weekdayDrives), decimals: 0)) / \(Fmt.distance(km(weekendDrives), decimals: 0))")
                        .monospacedDigit()
                }
                LabeledContent(String(localized: "Time")) {
                    Text(verbatim: "\(Fmt.duration(minutes(weekdayDrives))) / \(Fmt.duration(minutes(weekendDrives)))")
                        .monospacedDigit()
                }
                LabeledContent(String(localized: "Drives")) {
                    Text(verbatim: "\(weekdayDrives.count.formatted()) / \(weekendDrives.count.formatted())")
                        .monospacedDigit()
                }
            } header: {
                Text("Weekdays / Weekend")
            }

            Section {
                Heatmap(grid: heat, days: orderedDays, tint: .blue)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } header: {
                Text("When you drive")
            } footer: {
                Text("Distance driven per weekday and hour, across every drive.")
            }
        }
        .navigationTitle("Destinations")
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }
}

// a ranked destination leads here: every drive that ended there, with the totals
// on top, the same way the charging ranking works
struct PlaceDrivesView: View {
    let name: String
    let drives: [Drive]
    var heaterDrives: Set<Int> = []

    // the same filter the ranking was built from
    private var here: [Drive] {
        let unknown = String(localized: "Unknown location")
        return drives
            .filter { ($0.endAddress ?? unknown) == name }
            .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        let here = here
        let run = here.map { DetailTarget.drive(id: $0.driveId, day: $0.startDate) }
        List {
            Section {
                LabeledContent(String(localized: "Drives")) {
                    Text(verbatim: here.count.formatted())
                        .monospacedDigit()
                }
                LabeledContent(String(localized: "Distance")) {
                    Text(verbatim: Fmt.distance(here.reduce(0) { $0 + $1.distance }))
                        .monospacedDigit()
                }
                LabeledContent(String(localized: "Time")) {
                    Text(verbatim: Fmt.duration(here.compactMap(\.durationMin).reduce(0, +)))
                        .monospacedDigit()
                }
            } header: {
                Text("Total")
            }
            Section {
                ForEach(Array(here.enumerated()), id: \.element.id) { i, drive in
                    NavigationLink(value: DetailRoute(targets: run, index: i)) {
                        DriveRow(drive: drive, heaterUsed: heaterDrives.contains(drive.driveId))
                    }
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }
}
