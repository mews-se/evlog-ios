import Charts
import SwiftUI

struct TempConsumptionView: View {
    let drives: [Drive]

    struct Sample {
        let date: Date
        let celsius: Double
        let whPerKm: Double
        let km: Double
    }

    struct Bucket: Identifiable {
        let lower: Double
        let width: Double
        var distance = 0.0
        var energy = 0.0
        var count = 0

        var id: Double { lower }
        var upper: Double { lower + width }
        // the aggregate is distance-weighted: total energy over total distance,
        // so a short errand cannot outvote the commute
        var whPerKm: Double { distance > 0 ? energy / distance * 1000 : 0 }
    }

    struct Fifth {
        let whPerKm: Double
        let coldest: Double
        let warmest: Double
    }

    static func samples(for drives: [Drive]) -> [Sample] {
        drives.compactMap { drive in
            guard let celsius = drive.outsideTempAvg,
                  let whPerKm = drive.consumptionWhPerKm,
                  drive.distance >= 1 else { return nil }
            return Sample(date: drive.startDate, celsius: celsius, whPerKm: whPerKm, km: drive.distance)
        }
    }

    // buckets live in display units so the bands land on even numbers either way
    static func buckets(for samples: [Sample]) -> [Bucket] {
        let width: Double = Units.imperial ? 5 : 2
        var byLower: [Double: Bucket] = [:]
        for sample in samples {
            let lower = (Units.temperature(sample.celsius) / width).rounded(.down) * width
            var bucket = byLower[lower] ?? Bucket(lower: lower, width: width)
            bucket.distance += sample.km
            bucket.energy += sample.whPerKm * sample.km / 1000
            bucket.count += 1
            byLower[lower] = bucket
        }
        return byLower.values.filter { $0.count >= 3 }.sorted { $0.lower < $1.lower }
    }

    // a fifth of the distance, not of the drive count - the same weighting the chart uses
    static func fifth(of samples: [Sample], coldest: Bool) -> Fifth? {
        guard samples.count >= 10 else { return nil }
        let sorted = samples.sorted { coldest ? $0.celsius < $1.celsius : $0.celsius > $1.celsius }
        let target = sorted.reduce(0) { $0 + $1.km } / 5
        var km = 0.0, energy = 0.0
        var temps: [Double] = []
        for sample in sorted {
            km += sample.km
            energy += sample.whPerKm * sample.km / 1000
            temps.append(sample.celsius)
            if km >= target { break }
        }
        guard km > 0, let low = temps.min(), let high = temps.max() else { return nil }
        return Fifth(whPerKm: energy / km * 1000, coldest: low, warmest: high)
    }

    private var samples: [Sample] { Self.samples(for: drives) }
    private var buckets: [Bucket] { Self.buckets(for: samples) }
    private var cold: Fifth? { Self.fifth(of: samples, coldest: true) }
    private var warm: Fifth? { Self.fifth(of: samples, coldest: false) }

    private var average: Double {
        let distance = buckets.reduce(0) { $0 + $1.distance }
        let energy = buckets.reduce(0) { $0 + $1.energy }
        return distance > 0 ? energy / distance * 1000 : 0
    }

    private var period: String {
        let dates = samples.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return "–" }
        let from = first.formatted(.dateTime.month(.abbreviated).year().locale(.app))
        let to = last.formatted(.dateTime.month(.abbreviated).year().locale(.app))
        return from == to ? from : "\(from) – \(to)"
    }

    private var differencePct: Double? {
        guard let cold, let warm, warm.whPerKm > 0 else { return nil }
        return (cold.whPerKm / warm.whPerKm - 1) * 100
    }

    private func plotted(_ whPerKm: Double) -> Double {
        Units.imperial ? whPerKm * Units.kmPerMile : whPerKm
    }

    // the marks float free of zero, so the axis follows the data instead of
    // dragging an empty 0-150 band along under every chart
    private var yDomain: ClosedRange<Double> {
        let values = buckets.map { plotted($0.whPerKm) } + [plotted(average)]
        guard let low = values.min(), let high = values.max(), high > low else { return 0...1 }
        var lower = (low / 50).rounded(.down) * 50
        if low - lower < 10 { lower -= 25 }
        var upper = (high / 50).rounded(.up) * 50
        if upper - high < 10 { upper += 25 }
        return max(0, lower)...upper
    }

    // cold to warm across the data's own span: blue through teal and amber to red
    private func tempColor(_ bucket: Bucket) -> Color {
        let lowers = buckets.map(\.lower)
        guard let coldest = lowers.min(), let warmest = lowers.max(), warmest > coldest else { return .purple }
        let t = (bucket.lower - coldest) / (warmest - coldest)
        return Color(hue: 0.62 - 0.60 * t, saturation: 0.7, brightness: 0.95)
    }

    private func span(_ fifth: Fifth) -> String {
        "\(Fmt.temp(fifth.coldest)) to \(Fmt.temp(fifth.warmest))"
    }

    var body: some View {
        List {
            if buckets.isEmpty {
                ContentUnavailableView("No temperature data", systemImage: "thermometer.medium")
            } else {
                Section {
                    consumptionChart
                        .frame(height: 260)
                        .padding(.vertical, 8)
                    LabeledContent(String(localized: "Average")) {
                        Text(verbatim: Fmt.consumption(average))
                            .monospacedDigit()
                    }
                    LabeledContent(String(localized: "Drives")) {
                        Text(verbatim: samples.count.formatted())
                            .monospacedDigit()
                    }
                    LabeledContent(String(localized: "Period")) {
                        Text(verbatim: period)
                    }
                } footer: {
                    Text("Net consumption for every drive of at least a kilometre, grouped by outside temperature. Groups with fewer than three drives are hidden. The dashed line marks the average.")
                }

                if let cold, let warm, let differencePct {
                    Section {
                        PlaceRow(name: String(localized: "Coldest fifth"), detail: span(cold),
                                 value: Fmt.consumption(cold.whPerKm), tint: .cyan)
                        PlaceRow(name: String(localized: "Warmest fifth"), detail: span(warm),
                                 value: Fmt.consumption(warm.whPerKm), tint: .orange)
                        LabeledContent(String(localized: "Difference")) {
                            Text(verbatim: (differencePct >= 0 ? "+" : "") + Fmt.pct(differencePct, decimals: 0))
                                .monospacedDigit()
                        }
                    } footer: {
                        Text("The fifth of the distance driven in the coldest weather against the fifth driven in the warmest.")
                    }
                }

                Section {
                    distanceChart
                        .frame(height: 140)
                        .padding(.vertical, 8)
                } footer: {
                    Text("How much of the driving happened at each temperature.")
                }
            }
        }
        .navigationTitle("Temperature and consumption")
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }

    private var consumptionChart: some View {
        Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    xStart: .value("Temperature" as String, bucket.lower + bucket.width * 0.06),
                    xEnd: .value("Temperature" as String, bucket.upper - bucket.width * 0.06),
                    y: .value("Consumption" as String, plotted(bucket.whPerKm)),
                    height: .fixed(16)
                )
                .foregroundStyle(tempColor(bucket))
                .cornerRadius(8)
            }
            RuleMark(y: .value("Average" as String, plotted(average)))
                .foregroundStyle(.gray)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Average")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
        .chartXAxis { temperatureAxis }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: .stride(by: 25.0))
        }
        .chartYAxisLabel(alignment: .trailing) {
            Text(verbatim: Units.imperial ? "Wh/mi" : "Wh/km")
        }
    }

    private var distanceChart: some View {
        Chart(buckets) { bucket in
            RectangleMark(
                xStart: .value("Temperature" as String, bucket.lower + bucket.width * 0.06),
                xEnd: .value("Temperature" as String, bucket.upper - bucket.width * 0.06),
                yStart: .value("Distance" as String, 0),
                yEnd: .value("Distance" as String, Units.distance(bucket.distance))
            )
            .foregroundStyle(.blue.opacity(0.6).gradient)
            .cornerRadius(2)
        }
        .chartXAxis { temperatureAxis }
        .chartYAxisLabel(alignment: .trailing) {
            Text(verbatim: Units.imperial ? "mi" : "km")
        }
    }

    private var temperatureAxis: some AxisContent {
        AxisMarks(values: .stride(by: 10.0)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let temp = value.as(Double.self) {
                    Text(verbatim: "\(Int(temp))°")
                }
            }
        }
    }
}
