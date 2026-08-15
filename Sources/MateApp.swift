import SwiftUI

@main
struct MateApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @AppStorage("serverURL") private var serverURL = "http://10.0.0.185:8080"
    @AppStorage("carID") private var carID = 1

    var api: APIClient { APIClient(baseURL: serverURL) }

    var body: some View {
        TabView {
            DashboardView(api: api, carID: carID)
                .tabItem { Label("Översikt", systemImage: "gauge.with.dots.needle.50percent") }
            DrivesView(api: api, carID: carID)
                .tabItem { Label("Resor", systemImage: "road.lanes") }
            ChargesView(api: api, carID: carID)
                .tabItem { Label("Laddning", systemImage: "bolt.fill") }
            SettingsView()
                .tabItem { Label("Inställningar", systemImage: "gearshape.fill") }
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
            Button("Försök igen", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}
