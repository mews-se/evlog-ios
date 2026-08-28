import SwiftUI

struct SettingsView: View {
    @AppStorage(Pref.server.key) private var serverURL = Pref.server.value
    @AppStorage(Pref.grafana.key) private var grafanaURL = Pref.grafana.value
    @AppStorage(Pref.teslamate.key) private var teslamateURL = Pref.teslamate.value
    @AppStorage(Pref.carID.key) private var carID = Pref.carID.value
    @AppStorage(Pref.tessieToken.key) private var tessieToken = Pref.tessieToken.value
    @AppStorage(Pref.units.key) private var units = Pref.units.value
    @AppStorage(Pref.demoMode.key) private var demoMode = Pref.demoMode.value

    @FocusState private var editing: Bool

    @State private var cars: [Car] = []
    @State private var testResult: String?
    @State private var tessieResult: String?

    // the server field edits a draft: a write-through per keystroke would flip
    // Demo.isActive mid-word and RootView's id would throw the keyboard out
    @State private var serverDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // reads the ACTIVE state: on a first launch with no server the
                    // mode is on by itself, and stays until an address arrives below
                    Toggle("Demo mode", isOn: Binding(
                        get: { Demo.isActive },
                        set: { demoMode = $0 }
                    ))
                    .disabled(serverURL.isEmpty)
                } footer: {
                    Text("Built-in example data instead of a server. The app starts here until a TeslaMate API address is in place.")
                }

                Section {
                    TextField("http://server:8080" as String, text: $serverDraft)
                        .keyboardType(.URL)
                        .focused($editing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { commitServer() }
                    Button("Test connection") {
                        Task { await testConnection() }
                    }
                    if let testResult {
                        Text(verbatim: testResult)
                            .font(.footnote)
                            .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                    }
                } header: {
                    Text(verbatim: "TeslaMate API")
                } footer: {
                    Text("The teslamateapi container. Drives, charges and vehicle status all come from here.")
                }

                Section {
                    TextField("http://server:3000" as String, text: $grafanaURL)
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
                    TextField("http://server:4000" as String, text: $teslamateURL)
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
                        Text(verbatim: tessieResult)
                            .font(.footnote)
                            .foregroundStyle(tessieResult.hasPrefix("✓") ? .green : .red)
                    }
                } header: {
                    Text(verbatim: "Tessie")
                } footer: {
                    Text("Optional. Fills in charging costs that TeslaMate lacks, for example Superchargers. The key is stored on this device only.")
                }

                Section {
                    Picker("Units", selection: $units) {
                        Text("Metric").tag("metric")
                        Text("Imperial").tag("imperial")
                    }
                } footer: {
                    Text("The region sets the default. TeslaMate's data is metric either way; this only changes what is shown.")
                }

                Section {
                    NavigationLink("About EVLog") { AboutView() }
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
            .onAppear { serverDraft = serverURL }
            .onDisappear { commitServer() }
            .onChange(of: editing) { _, focused in
                if !focused { commitServer() }
            }
        }
    }

    private func commitServer() {
        if serverURL != serverDraft { serverURL = serverDraft }
    }

    private func testConnection() async {
        do {
            // the test is about the address on screen, never the demo data
            let cars = try await APIClient(baseURL: serverDraft, demo: false).cars()
            self.cars = cars
            let names = cars.map(\.name).joined(separator: ", ")
            testResult = String(localized: "✓ Connected – found \(names)")
            // a proven address counts as configured - on a first run this alone
            // lifts the app out of the demo. the pause lets the green line land
            try? await Task.sleep(for: .seconds(1))
            commitServer()
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
    }

    private func loadCars() async {
        cars = (try? await APIClient(baseURL: serverURL, demo: false).cars()) ?? []
        // a lone car with an id other than the saved one would otherwise leave the app on a 404 with no picker
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
