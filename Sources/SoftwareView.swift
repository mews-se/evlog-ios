import SwiftUI

struct SoftwareView: View {
    let api: APIClient
    let carID: Int
    var current: String?

    @State private var updates: [SoftwareUpdate] = []
    @State private var error: String?

    private var currentShort: String? {
        guard let first = current?.components(separatedBy: " ").first, !first.isEmpty else { return nil }
        return first
    }

    var body: some View {
        Group {
            if !updates.isEmpty {
                List {
                    Section {
                        ForEach(updates) { update in
                            UpdateRow(update: update, isCurrent: update.shortVersion == currentShort)
                        }
                    } header: {
                        Text("Installed versions")
                    } footer: {
                        Text("Release notes come from notateslaapp.com, which is not affiliated with Tesla or TeslaMate.")
                    }
                }
            } else if let error {
                ErrorCard(message: error) { Task { await load() } }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Software")
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
        .task { await load() }
    }

    private func load() async {
        do {
            updates = try await api.updates(carID: carID).sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            error = nil
        } catch {
            if updates.isEmpty { self.error = error.localizedDescription }
        }
    }
}

struct UpdateRow: View {
    let update: SoftwareUpdate
    var isCurrent = false

    var body: some View {
        if let url = update.releaseNotesURL {
            Link(destination: url) { row }
        } else {
            row
        }
    }

    private var row: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: update.shortVersion ?? "–")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if isCurrent {
                        Text("Installed")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(verbatim: Fmt.date(update.endDate ?? update.startDate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if update.releaseNotesURL != nil {
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
