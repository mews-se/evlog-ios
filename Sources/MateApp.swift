import SwiftUI

@main
struct MateApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// nycklarna och deras standardvärden på ett ställe. literalerna låg utspridda i
// fem vyer, där samma nyckel kunde få olika default utan att något sa ifrån
enum Pref {
    static let server = (key: "serverURL", value: "http://10.0.0.185:8080")
    static let grafana = (key: "grafanaURL", value: "http://10.0.0.185:3000")
    static let teslamate = (key: "teslamateURL", value: "http://10.0.0.185:4000")
    static let tessieToken = (key: "tessieToken", value: "")
    static let language = (key: "appLanguage", value: "system")
    static let carID = (key: "carID", value: 1)
}

struct RootView: View {
    @AppStorage(Pref.server.key) private var serverURL = Pref.server.value
    @AppStorage(Pref.carID.key) private var carID = Pref.carID.value

    var api: APIClient { APIClient(baseURL: serverURL) }

    var body: some View {
        TabView {
            DashboardView(api: api, carID: carID)
                .tabItem { Label("Overview", systemImage: "gauge.with.dots.needle.50percent") }
            DrivesView(api: api, carID: carID)
                .tabItem { Label("Drives", systemImage: "road.lanes") }
            ChargesView(api: api, carID: carID)
                .tabItem { Label("Charges", systemImage: "bolt.fill") }
            StatsView(api: api, carID: carID)
                .tabItem { Label("Statistics", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
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
