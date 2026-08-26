import SwiftUI

struct BatteryHealthView: View {
    let health: BatteryHealth?

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
                    Text("Estimated from the rated range at the end of your last 100 charges, using the same method as TeslaMate's battery health dashboard. Cell chemistry and temperature make single readings noisy.")
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
