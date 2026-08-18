import SwiftUI

struct AboutView: View {
    private static let developer = "Martin Stockzell"

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
                    Text("Made by \(Self.developer)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }

            Section {
                LinkRow(title: String(localized: "Source code"), detail: "GitHub",
                        url: "https://github.com/mews-se/evlog-ios")
                LabeledContent(String(localized: "License")) { Text(verbatim: "MIT") }
            } header: {
                Text("Open source")
            } footer: {
                Text("EVLog is free software. No ads, no tracking and nothing to buy – and the code is there to read, build and change.")
            }

            Section {
                LinkRow(title: "TeslaMate", detail: String(localized: "Drives, charges and vehicle data"),
                        url: "https://github.com/teslamate-org/teslamate")
                LinkRow(title: "supercharge.info", detail: String(localized: "Supercharger locations"),
                        url: "https://supercharge.info")
                LinkRow(title: "notateslaapp.com", detail: String(localized: "Software release notes"),
                        url: "https://www.notateslaapp.com")
                if !tessieToken.isEmpty {
                    LinkRow(title: "Tessie", detail: String(localized: "Charging costs TeslaMate lacks"),
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
    let title: String
    let detail: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .foregroundStyle(.primary)
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
