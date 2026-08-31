import SwiftUI

@main
struct EVLogApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// the keys and their defaults in one place. the literals were spread across five
// views, where the same key could pick up different defaults with nothing to say so
enum Pref {
    static let server = (key: "serverURL", value: "")
    static let grafana = (key: "grafanaURL", value: "")
    static let teslamate = (key: "teslamateURL", value: "")
    static let tessieToken = (key: "tessieToken", value: "")
    static let units = (key: "units", value: Locale.current.measurementSystem == .metric ? "metric" : "imperial")
    static let carID = (key: "carID", value: 1)
    static let timelinePeriod = (key: "timelinePeriod", value: TimelinePeriod.month.rawValue)
    static let demoMode = (key: "demoMode", value: false)
    static let visitedMapStyle = (key: "visitedMapStyle", value: VisitedView.MapStylePick.standard.rawValue)
}

struct RootView: View {
    @AppStorage(Pref.server.key) private var serverURL = Pref.server.value
    @AppStorage(Pref.carID.key) private var carID = Pref.carID.value

    // formatted strings read the choice outside SwiftUI's view state, so a change
    // rebuilds the tree the way the language picker used to
    @AppStorage(Pref.units.key) private var units = Pref.units.value
    @AppStorage(Pref.demoMode.key) private var demoMode = Pref.demoMode.value

    @State private var selection = 0
    @State private var overviewPath = NavigationPath()
    @State private var timelinePath = NavigationPath()
    @State private var statsPath = NavigationPath()

    var api: APIClient { APIClient(baseURL: serverURL) }

    var body: some View {
        TabView(selection: $selection) {
            DashboardView(api: api, carID: carID, path: $overviewPath)
                .tabItem { Label("Overview", systemImage: "gauge.with.dots.needle.50percent") }
                .tag(0)
            TimelineView(api: api, carID: carID, path: $timelinePath)
                .tabItem { Label("Timeline", systemImage: "calendar.day.timeline.left") }
                .tag(1)
            StatsView(api: api, carID: carID, path: $statsPath)
                .tabItem { Label("Statistics", systemImage: "chart.bar.fill") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        // switching tabs should land on the tab's root, not where you last stood
        .onChange(of: selection) { _, _ in
            overviewPath = NavigationPath()
            timelinePath = NavigationPath()
            statsPath = NavigationPath()
        }
        // flipping units or demo rebuilds the tree so every view reloads its data
        .id("\(units)|\(demoMode)|\(serverURL.isEmpty)")
        .environment(\.locale, .app)
    }
}

enum OverviewRoute: Hashable {
    case visited(lat: Double?, lon: Double?)
    case software(version: String?)
    case batteryHealth
    case countries
    case range(lat: Double?, lon: Double?, km: Double?)
}

enum StatsRoute: Hashable {
    case period(Date, StatsView.Granularity)
    case day(Date)
    case charging
    case temperature
    case destinations
    case destination(String)
    case place(String)
}

struct ErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(verbatim: message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}
