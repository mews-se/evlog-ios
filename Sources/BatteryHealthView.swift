import Charts
import SwiftUI

struct BatteryHealthView: View {
    let health: BatteryHealth?
    var readings: [CapacityReading] = []

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
