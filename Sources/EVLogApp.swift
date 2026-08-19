import SwiftUI

@main
struct EVLogApp: App {
    init() {
        AppLanguage.apply(UserDefaults.standard.string(forKey: Pref.language.key) ?? Pref.language.value)
    }

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
    static let language = (key: "appLanguage", value: "system")
    static let carID = (key: "carID", value: 1)
}

struct RootView: View {
    @AppStorage(Pref.server.key) private var serverURL = Pref.server.value
    @AppStorage(Pref.carID.key) private var carID = Pref.carID.value

    @AppStorage(Pref.language.key) private var appLanguage = Pref.language.value

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
        .id(appLanguage)
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
}

struct ErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}
