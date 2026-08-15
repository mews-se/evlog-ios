import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = "http://10.0.0.185:8080"
    @AppStorage("carID") private var carID = 1

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
                    Button("Testa anslutning") {
                        Task { await testConnection() }
                    }
                    if let testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                    }
                }

                if cars.count > 1 {
                    Section("Bil") {
                        Picker("Bil", selection: $carID) {
                            ForEach(cars) { car in
                                Text(car.name).tag(car.carId)
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Datakälla", value: "TeslaMate via teslamateapi")
                } footer: {
                    Text("Appen läser din självhostade TeslaMate-databas. Ingen data lämnar ditt nätverk.")
                }
            }
            .navigationTitle("Inställningar")
            .task { await loadCars() }
        }
    }

    private func testConnection() async {
        do {
            let cars = try await APIClient(baseURL: serverURL).cars()
            self.cars = cars
            testResult = "✓ Ansluten – hittade \(cars.map(\.name).joined(separator: ", "))"
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
    }

    private func loadCars() async {
        cars = (try? await APIClient(baseURL: serverURL).cars()) ?? []
    }
}
