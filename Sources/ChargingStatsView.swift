import SwiftUI

struct ChargingStatsView: View {
    let charges: [Charge]
    var tessieCosts: [Int: Double] = [:]

    private func cost(of charge: Charge) -> Double {
        charge.displayCost ?? tessieCosts[charge.chargeId] ?? 0
    }

    // MARK: - Charging locations

    struct Place: Identifiable {
        let name: String
        var energy = 0.0
        var cost = 0.0
        var count = 0

        var id: String { name }
    }

    private var places: [Place] {
        var byName: [String: Place] = [:]
        for charge in charges {
            let name = charge.address ?? String(localized: "Unknown location")
            var place = byName[name] ?? Place(name: name)
            place.energy += charge.chargeEnergyAdded ?? 0
            place.cost += cost(of: charge)
            place.count += 1
            byName[name] = place
        }
        return Array(byName.values)
    }

    private var topByEnergy: [Place] {
        Array(places.filter { $0.energy > 0 }.sorted { $0.energy > $1.energy }.prefix(5))
    }

    private var topByCost: [Place] {
        Array(places.filter { $0.cost > 0 }.sorted { $0.cost > $1.cost }.prefix(5))
    }

    // MARK: - AC/DC

    private var dc: [Charge] { charges.filter(\.isDC) }
    private var ac: [Charge] { charges.filter { !$0.isDC } }

    private func energy(_ list: [Charge]) -> Double { list.compactMap(\.chargeEnergyAdded).reduce(0, +) }
    private func minutes(_ list: [Charge]) -> Double { list.compactMap(\.durationMin).reduce(0, +) }

    // MARK: - Heatmap

    // weekday (0 = Sunday, as Calendar has it) against hour, energy summed
    private var heat: [[Double]] {
        var grid = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        let calendar = Calendar.current
        for charge in charges {
            let weekday = calendar.component(.weekday, from: charge.startDate) - 1
            let hour = calendar.component(.hour, from: charge.startDate)
            grid[weekday][hour] += charge.chargeEnergyAdded ?? 0
        }
        return grid
    }

    // the rows follow the first weekday in the user's calendar
    private var orderedDays: [Int] {
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { (first + $0) % 7 }
    }

    var body: some View {
        List {
            Section {
                ForEach(topByEnergy) { place in
                    NavigationLink(value: StatsRoute.place(place.name)) {
                        PlaceRow(name: place.name, detail: "\(place.count)", value: Fmt.kwh(place.energy), tint: .green)
                    }
                }
            } header: {
                Text("Most energy")
            }

            if !topByCost.isEmpty {
                Section {
                    ForEach(topByCost) { place in
                        NavigationLink(value: StatsRoute.place(place.name)) {
                            PlaceRow(name: place.name, detail: Fmt.kwh(place.energy), value: Fmt.kr(place.cost), tint: .blue)
                        }
                    }
                } header: {
                    Text("Most expensive")
                }
            }

            Section {
                SplitBar(acEnergy: energy(ac), dcEnergy: energy(dc))
                LabeledContent(String(localized: "Energy")) {
                    Text(verbatim: "\(Fmt.kwh(energy(ac))) / \(Fmt.kwh(energy(dc)))")
                        .monospacedDigit()
                }
                LabeledContent(String(localized: "Time")) {
                    Text(verbatim: "\(Fmt.duration(minutes(ac))) / \(Fmt.duration(minutes(dc)))")
                        .monospacedDigit()
                }
                LabeledContent(String(localized: "Charges")) {
                    Text(verbatim: "\(ac.count) / \(dc.count)")
                        .monospacedDigit()
                }
            } header: {
                Text("AC / DC")
            }

            Section {
                Heatmap(grid: heat, days: orderedDays)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } header: {
                Text("When you charge")
            } footer: {
                Text("Energy added per weekday and hour, across every charge.")
            }
        }
        .navigationTitle("Charging statistics")
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }
}

// a ranked place leads here: every charge there, with the row's totals on top so
// nothing has to be added up by hand. both rankings come to the same page, since a
// place is a place and the two lists are only different ways in
struct PlaceChargesView: View {
    let name: String
    let charges: [Charge]
    let drives: [Drive]
    var tessieCosts: [Int: Double] = [:]

    // the same filter the ranking was built from, joined the way the timeline joins
    private var groups: [ChargeGroup] {
        let unknown = String(localized: "Unknown location")
        let here = charges.filter { ($0.address ?? unknown) == name }
        return ChargeGroup.stitch(here, drives: drives).sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        let groups = groups
        let run = groups.map { DetailTarget.charge(ids: $0.parts.map(\.chargeId), address: $0.address) }
        List {
            Section {
                ChargeSummaryCard(title: "Total", groups: groups, tessieCosts: tessieCosts)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(Array(groups.enumerated()), id: \.element.id) { i, group in
                    NavigationLink(value: DetailRoute(targets: run, index: i)) {
                        ChargeRow(group: group, tessieCosts: tessieCosts, showsPlace: false)
                    }
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }
}

struct PlaceRow: View {
    let name: String
    let detail: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .padding(.vertical, 2)
    }
}

struct SplitBar: View {
    let acEnergy: Double
    let dcEnergy: Double

    private var total: Double { acEnergy + dcEnergy }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if total > 0 {
                        Capsule().fill(.green)
                            .frame(width: geo.size.width * acEnergy / total)
                        Capsule().fill(.red)
                    }
                }
            }
            .frame(height: 10)
            HStack {
                Label(Fmt.pct(total > 0 ? acEnergy / total * 100 : 0, decimals: 0) + " AC", systemImage: "circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Label(Fmt.pct(total > 0 ? dcEnergy / total * 100 : 0, decimals: 0) + " DC", systemImage: "circle.fill")
                    .foregroundStyle(.red)
            }
            .font(.caption2)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 4)
    }
}

struct Heatmap: View {
    let grid: [[Double]]
    let days: [Int]

    private var peak: Double { grid.flatMap { $0 }.max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(days, id: \.self) { day in
                HStack(spacing: 2) {
                    Text(verbatim: Calendar.current.veryShortWeekdaySymbols[day])
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.green.opacity(intensity(day, hour)))
                            .frame(maxWidth: .infinity)
                            .frame(height: 13)
                    }
                }
            }
            HStack(spacing: 2) {
                Color.clear.frame(width: 14, height: 1)
                ForEach(0..<24, id: \.self) { hour in
                    Text(verbatim: hour % 6 == 0 ? "\(hour)" : "")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // empty cells should read as a cell, not as a hole
    private func intensity(_ day: Int, _ hour: Int) -> Double {
        guard peak > 0 else { return 0.08 }
        let value = grid[day][hour]
        return value <= 0 ? 0.08 : 0.15 + 0.85 * (value / peak)
    }
}
