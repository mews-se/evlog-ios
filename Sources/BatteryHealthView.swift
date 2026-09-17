import Charts
import SwiftUI

struct BatteryHealthView: View {
    let health: BatteryHealth?
    var readings: [CapacityReading] = []
    var times: [LevelTime] = []

    var body: some View {
        ScrollView {
            if let health {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "battery.100percent.bolt", title: String(localized: "Degradation"),
                                 value: Fmt.pct(health.degradation), tint: .teal, valueTint: .teal)
                        StatTile(icon: "heart.fill", title: String(localized: "Battery health"),
                                 value: Fmt.pct(health.health), tint: .green, valueTint: .green)
                        StatTile(icon: "bolt.fill", title: String(localized: "Capacity now"),
                                 value: Fmt.kwh(health.currentCapacity), tint: .blue)
                        StatTile(icon: "bolt.badge.clock", title: String(localized: "Capacity when new"),
                                 value: Fmt.kwh(health.maxCapacity), tint: .secondary)
                        StatTile(icon: "point.topleft.down.to.point.bottomright.curvepath", title: String(localized: "Range at 100 %"),
                                 value: Fmt.distance(health.currentRange, decimals: 0), tint: .blue)
                        StatTile(icon: "arrow.down.right", title: String(localized: "Range lost"),
                                 value: Fmt.distance(health.lostRange, decimals: 0), tint: .orange)
                    }
                    if readings.count >= 5 {
                        CapacityChart(readings: readings, kwhPerKm: health.kwhPerKm, whenNew: health.maxCapacity)
                    }
                    Text("Estimated from the rated range at the end of each charge, scaled to a full battery: when new is the strongest of those readings, now is the average of your last 20 charges. Cell chemistry and temperature make single readings noisy.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !times.isEmpty {
                        HStack(spacing: 12) {
                            StatTile(icon: "battery.100percent", title: String(localized: "Above 80 %"),
                                     value: Fmt.pct(LevelTimeChart.share(times) { $0 > 80 }), tint: .orange)
                            StatTile(icon: "battery.25percent", title: String(localized: "Below 20 %"),
                                     value: Fmt.pct(LevelTimeChart.share(times) { $0 < 20 }), tint: .orange)
                        }
                        LevelTimeChart(times: times)
                    }
                }
                .padding(.horizontal)
            } else {
                ContentUnavailableView("Not enough charging data yet", systemImage: "battery.100percent.bolt")
                    .padding(.top, 80)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Battery")
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }
}

// capacity against the odometer: a point per charge and a line through the middle of
// them, so the eye can tell a slope from the scatter
struct CapacityChart: View {
    let readings: [CapacityReading]
    let kwhPerKm: Double
    let whenNew: Double

    struct Point: Identifiable {
        let id: Int
        let distance: Double
        let kwh: Double
    }

    // the line is the running median of the nearest readings, ten to each side where there
    // are that many. a median rather than a mean, so one odd charge cannot bend it
    static func series(_ readings: [CapacityReading], kwhPerKm: Double) -> (scatter: [Point], trend: [Point]) {
        let scatter = readings.map { reading in
            Point(id: reading.id, distance: Units.distance(reading.odometerKm), kwh: reading.fullRangeKm * kwhPerKm)
        }
        guard scatter.count >= 9 else { return (scatter, []) }
        let trend = scatter.indices.map { i in
            let window = scatter[max(0, i - 10)...min(scatter.count - 1, i + 10)].map(\.kwh).sorted()
            return Point(id: scatter[i].id, distance: scatter[i].distance, kwh: window[window.count / 2])
        }
        return (scatter, trend)
    }

    // the axis follows the readings, not zero: a battery losing a few kWh of eighty would
    // otherwise be a flat line along the top
    private static func yDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max(1, (high - low) * 0.15)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        let (scatter, trend) = Self.series(readings, kwhPerKm: kwhPerKm)
        VStack(alignment: .leading, spacing: 8) {
            Text("Capacity over mileage")
                .font(.subheadline.weight(.semibold))
            Chart {
                ForEach(scatter) { point in
                    PointMark(x: .value("Distance" as String, point.distance), y: .value("Capacity" as String, point.kwh))
                        .foregroundStyle(.blue.opacity(0.35))
                        .symbolSize(18)
                }
                ForEach(trend) { point in
                    LineMark(x: .value("Distance" as String, point.distance), y: .value("Trend" as String, point.kwh))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("When new" as String, whenNew))
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Capacity when new")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: Self.yDomain(scatter.map(\.kwh) + [whenNew]))
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .chartYAxisLabel(alignment: .trailing) {
                Text(verbatim: "kWh")
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let distance = value.as(Double.self) {
                            Text(verbatim: distance.formatted(.number.notation(.compactName)))
                        }
                    }
                }
            }
            .chartXAxisLabel(alignment: .trailing) {
                Text(verbatim: Units.imperial ? "mi" : "km")
            }
            .frame(height: 220)
            Text("One reading per finished charge: the rated range at its end, scaled to a full battery and turned into capacity. The line is the median of the nearest readings, so a slope shows through the noise.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// where the battery has stood: the share of all logged time at each charge level, in
// steps of five, with the time outside the twenty to eighty band picked out
struct LevelTimeChart: View {
    let times: [LevelTime]

    struct Bin: Identifiable {
        let lower: Int
        let share: Double
        var id: Int { lower }
        var upper: Int { lower + 5 }
        var outside: Bool { upper <= 20 || lower >= 80 }
    }

    // a bin runs from just above its lower edge up to and including its upper, so eighty,
    // the limit most owners charge to, lands in the bar below the line rather than above it
    static func bins(_ times: [LevelTime]) -> [Bin] {
        let total = times.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return [] }
        var seconds = [Int: Double]()
        for time in times {
            seconds[min(95, max(0, (time.level - 1) / 5 * 5)), default: 0] += time.seconds
        }
        return stride(from: 0, to: 100, by: 5).map { Bin(lower: $0, share: (seconds[$0] ?? 0) / total) }
    }

    // the share of all logged time, in percent, at the levels the test keeps
    static func share(_ times: [LevelTime], where keep: (Int) -> Bool) -> Double? {
        let total = times.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return nil }
        return times.filter { keep($0.level) }.reduce(0) { $0 + $1.seconds } * 100 / total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time at each charge level")
                .font(.subheadline.weight(.semibold))
            Chart(Self.bins(times)) { bin in
                RectangleMark(
                    xStart: .value("Level" as String, Double(bin.lower) + 0.3),
                    xEnd: .value("Level" as String, Double(bin.upper) - 0.3),
                    yStart: .value("Share" as String, 0),
                    yEnd: .value("Share" as String, bin.share * 100)
                )
                .foregroundStyle((bin.outside ? Color.orange : Color.blue).opacity(0.7).gradient)
                .cornerRadius(2)
            }
            .chartXScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [0.0, 20, 40, 60, 80, 100]) { value in
                    AxisGridLine()
                    if let level = value.as(Double.self) {
                        // the end labels hang inward, or the last one is dropped for want of room
                        AxisValueLabel(anchor: level == 100 ? .topTrailing : level == 0 ? .topLeading : .top) {
                            Text(verbatim: "\(Int(level)) %")
                        }
                    }
                }
            }
            .chartXAxisLabel(alignment: .trailing) {
                Text("Charge level")
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let share = value.as(Double.self) {
                            Text(verbatim: "\(Int(share)) %")
                        }
                    }
                }
            }
            .chartYAxisLabel(alignment: .trailing) {
                Text("Share of time")
            }
            .frame(height: 180)
            Text("Every stored level counts until the next reading, so a parked car counts for the level it sat at. Orange is the time outside the twenty to eighty band.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
