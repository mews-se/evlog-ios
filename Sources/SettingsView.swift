import SwiftUI

struct SettingsView: View {
    @AppStorage(Pref.server.key) private var serverURL = Pref.server.value
    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value
    @AppStorage(Pref.teslamate.key) private var teslamateURL = Pref.teslamate.value
    @AppStorage(Pref.carID.key) private var carID = Pref.carID.value
    @AppStorage(Pref.language.key) private var appLanguage = Pref.language.value
    @AppStorage(Pref.tessieToken.key) private var tessieToken = Pref.tessieToken.value

    @FocusState private var editing: Bool

    @State private var cars: [Car] = []
    @State private var testResult: String?
    @State private var tessieResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("http://server:8080", text: $serverURL)
                        .keyboardType(.URL)
                        .focused($editing)
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
                        .focused($editing)
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
                        .focused($editing)
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
                    TextField(String(localized: "API key"), text: $tessieToken)
                        .focused($editing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.footnote.monospaced())
                    if !tessieToken.isEmpty {
                        Button("Test connection") {
                            Task { await testTessie() }
                        }
                    }
                    if let tessieResult {
                        Text(tessieResult)
                            .font(.footnote)
                            .foregroundStyle(tessieResult.hasPrefix("✓") ? .green : .red)
                    }
                } header: {
                    Text(verbatim: "Tessie")
                } footer: {
                    Text("Optional. Fills in charging costs that TeslaMate lacks, for example Superchargers. The key is stored on this device only.")
                }

                Section {
                    Picker("Language", selection: $appLanguage) {
                        Text("System").tag("system")
                        Text(verbatim: "English").tag("en")
                        Text(verbatim: "Svenska").tag("sv")
                    }
                } header: {
                    Text("Language")
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
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editing = false }
                }
            }
            .task { await loadCars() }
            .onChange(of: appLanguage) { _, new in
                if new == "system" {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set([new], forKey: "AppleLanguages")
                }
                AppLanguage.apply(new)
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
        // en ensam bil med annat id än det sparade lämnar annars appen på 404 utan väljare
        if !cars.isEmpty, !cars.contains(where: { $0.carId == carID }) {
            carID = cars[0].carId
        }
    }

    private func testTessie() async {
        do {
            let vehicles = try await TessieClient(token: tessieToken).vehicles()
            let names = vehicles.compactMap { $0.lastState?.displayName ?? $0.vin }.joined(separator: ", ")
            tessieResult = String(localized: "✓ Connected – found \(names)")
        } catch {
            tessieResult = "✗ \(error.localizedDescription)"
        }
    }
}
