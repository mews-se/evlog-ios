import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = "http://10.0.0.185:8080"
    @AppStorage("grafanaURL") private var grafanaURL = "http://10.0.0.185:3000"
    @AppStorage("teslamateURL") private var teslamateURL = "http://10.0.0.185:4000"
    @AppStorage("carID") private var carID = 1
    @AppStorage("appLanguage") private var appLanguage = "system"

    @State private var cars: [Car] = []
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("http://server:8080", text: $serverURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Test connection") {
                        Task { await testConnection() }
                    }
                    if let testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                    }
                }

                Section {
                    TextField("http://server:3000", text: $grafanaURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text(verbatim: "Grafana")
                } footer: {
                    Text("Used for the visited places map.")
                }

                Section {
                    TextField("http://server:4000", text: $teslamateURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text(verbatim: "TeslaMate")
                } footer: {
                    Text("Used for editing charge costs.")
                }

                if cars.count > 1 {
                    Section("Car") {
                        Picker("Car", selection: $carID) {
                            ForEach(cars) { car in
                                Text(car.name).tag(car.carId)
                            }
                        }
                    }
                }

                Section {
                    Picker("Language", selection: $appLanguage) {
                        Text("System").tag("system")
                        Text(verbatim: "English").tag("en")
                        Text(verbatim: "Svenska").tag("sv")
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("Takes effect after the app is restarted.")
                }

                Section {
                    Link(destination: URL(string: "https://github.com/teslamate-org/teslamate")!) {
                        LabeledContent("Data source") {
                            Text(verbatim: "TeslaMate")
                        }
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text(verbatim: "This app is an unofficial community tool and is not affiliated with, endorsed by, or supported by the official TeslaMate project.")
                }
            }
            .navigationTitle("Settings")
            .task { await loadCars() }
            .onChange(of: appLanguage) { _, new in
                if new == "system" {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set([new], forKey: "AppleLanguages")
                }
            }
        }
    }

    private func testConnection() async {
        do {
            let cars = try await APIClient(baseURL: serverURL).cars()
            self.cars = cars
            let names = cars.map(\.name).joined(separator: ", ")
            testResult = String(localized: "✓ Connected – found \(names)")
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
    }

    private func loadCars() async {
        cars = (try? await APIClient(baseURL: serverURL).cars()) ?? []
    }
}
