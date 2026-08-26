import SwiftUI

struct CountriesView: View {
    let countries: [CountryStat]

    var body: some View {
        Group {
            if countries.isEmpty {
                ContentUnavailableView("No countries yet", systemImage: "globe")
            } else {
                List {
                    Section {
                        ForEach(countries) { country in
                            HStack(spacing: 12) {
                                Text(verbatim: country.flag)
                                    .font(.system(size: 30))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: country.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(country.drives) drives · last \(Fmt.date(country.lastVisit))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(verbatim: Fmt.distance(country.km, decimals: 0))
                                    .font(.callout.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    } footer: {
                        Text("Counted from where each drive ended.")
                    }
                }
            }
        }
        .navigationTitle("Countries")
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }
}
