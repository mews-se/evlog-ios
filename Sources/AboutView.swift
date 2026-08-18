import SwiftUI

struct AboutView: View {
    private static let developer = "Martin Stockzell (mews-se)"

    @AppStorage(Pref.tessieToken.key) private var tessieToken = Pref.tessieToken.value

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    Text(verbatim: "EVLog")
                        .font(.title2.weight(.semibold))
                    Text(verbatim: version)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("A project by \(Self.developer)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }

            Section {
                HStack(spacing: 13) {
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free and open source")
                            .font(.subheadline.weight(.semibold))
                        Text("No ads, no tracking, nothing to buy")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)

                LinkRow(icon: "chevron.left.forwardslash.chevron.right",
                        title: String(localized: "Source code", bundle: .current), detail: "GitHub",
                        url: "https://github.com/mews-se/evlog-ios")

                LabeledContent {
                    Text(verbatim: "MIT")
                } label: {
                    Label(String(localized: "License", bundle: .current), systemImage: "doc.plaintext")
                }
            } header: {
                Text("Open source")
            } footer: {
                Text("The code is there to read, build and change.")
            }

            Section {
                LinkRow(icon: "car.fill", title: "TeslaMate",
                        detail: String(localized: "Drives, charges and vehicle data", bundle: .current),
                        url: "https://github.com/teslamate-org/teslamate")
                LinkRow(icon: "bolt.fill", title: "supercharge.info",
                        detail: String(localized: "Supercharger locations", bundle: .current),
                        url: "https://supercharge.info")
                LinkRow(icon: "doc.text", title: "notateslaapp.com",
                        detail: String(localized: "Software release notes", bundle: .current),
                        url: "https://www.notateslaapp.com")
                if !tessieToken.isEmpty {
                    LinkRow(icon: "creditcard", title: "Tessie",
                            detail: String(localized: "Charging costs TeslaMate lacks", bundle: .current),
                            url: "https://tessie.com")
                }
            } header: {
                Text("Data sources")
            } footer: {
                Text(verbatim: "This app is an unofficial community tool and is not affiliated with, endorsed by, or supported by the official TeslaMate project.")
            }
        }
        .navigationTitle("About EVLog")
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }
}

private struct LinkRow: View {
    let icon: String
    let title: String
    let detail: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .foregroundStyle(.primary)
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
