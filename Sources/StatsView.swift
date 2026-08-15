import SwiftUI

struct StatsView: View {
    let api: APIClient
    let carID: Int

    @AppStorage("tessieToken") private var tessieToken = ""

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
    }

    @State private var granularity: Granularity = .month
    @State private var drives: [Drive] = []
    @State private var charges: [Charge] = []
    @State private var tessieCosts: [Int: Double] = [:]
    @State private var error: String?
    @State private var loaded = false

    private var buckets: [StatBucket] {
        let calendar = Calendar.current
        var byPeriod: [Date: StatBucket] = [:]

        func bucketStart(_ date: Date) -> Date {
            calendar.dateInterval(of: granularity.component, for: date)?.start ?? date
        }

        for drive in drives {
            let key = bucketStart(drive.startDate)
            var b = byPeriod[key] ?? StatBucket(period: key)
            b.distance += drive.distance
            b.driveMinutes += drive.durationMin ?? 0
            b.driveCount += 1
            b.energyConsumed += drive.energyConsumedNet ?? 0
            byPeriod[key] = b
        }
        for charge in charges {
            let key = bucketStart(charge.startDate)
            var b = byPeriod[key] ?? StatBucket(period: key)
            b.energyAdded += charge.chargeEnergyAdded ?? 0
            b.cost += charge.displayCost ?? tessieCosts[charge.chargeId] ?? 0
            b.chargeCount += 1
            byPeriod[key] = b
        }
        return byPeriod.values.sorted { $0.period > $1.period }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !drives.isEmpty || !charges.isEmpty {
                    List {
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
                                StatBucketRow(bucket: bucket, granularity: granularity)
                            }
                        }
                    }
                } else if let error {
                    ErrorCard(message: error) { Task { await load() } }
                } else if loaded {
                    ContentUnavailableView("No drives yet", systemImage: "chart.bar")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Statistics")
            .refreshable { await load() }
            .task { if !loaded { await load() } }
        }
    }

    private func load() async {
        do {
            async let d = api.allDrives(carID: carID)
            async let c = api.charges(carID: carID, results: 5000)
            drives = try await d
            charges = try await c
            error = nil
        } catch {
            if drives.isEmpty { self.error = error.localizedDescription }
        }
        loaded = true
        await loadTessieCosts()
    }

    private func loadTessieCosts() async {
        guard !tessieToken.isEmpty, !charges.isEmpty else { return }
        guard let vin = try? await api.cars().first(where: { $0.carId == carID })?.carDetails?.vin else { return }
        tessieCosts = (try? await TessieClient(token: tessieToken).missingCosts(for: charges, vin: vin)) ?? [:]
    }
}

struct StatBucket: Identifiable {
    let period: Date
    var distance = 0.0
    var driveMinutes = 0.0
    var driveCount = 0
    var energyConsumed = 0.0
    var energyAdded = 0.0
    var cost = 0.0
    var chargeCount = 0

    var id: Date { period }

    var consumption: Double? {
        distance > 0 && energyConsumed > 0 ? energyConsumed / distance * 1000 : nil
    }
}

struct StatBucketRow: View {
    let bucket: StatBucket
    let granularity: StatsView.Granularity

    private var title: String {
        switch granularity {
        case .week:
            let week = Calendar.current.component(.weekOfYear, from: bucket.period)
            let year = Calendar.current.component(.yearForWeekOfYear, from: bucket.period)
            return String(localized: "Week") + " \(week), \(year)"
        case .month:
            return bucket.period.formatted(.dateTime.month(.wide).year()).capitalized
        case .year:
            return bucket.period.formatted(.dateTime.year())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack {
                item(Fmt.km(bucket.distance, decimals: 0), .blue)
                item(Fmt.kwh(bucket.energyAdded), .green)
                item(bucket.cost > 0 ? Fmt.kr(bucket.cost) : "–", .primary)
            }
            HStack(spacing: 12) {
                Label("\(bucket.driveCount)", systemImage: "road.lanes")
                Label("\(bucket.chargeCount)", systemImage: "bolt")
                Label(Fmt.duration(bucket.driveMinutes), systemImage: "clock")
                if let consumption = bucket.consumption {
                    Label(Fmt.consumption(consumption), systemImage: "leaf")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
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
