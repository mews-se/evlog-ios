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

    // the middle gap between one update and the next, as TeslaMate's dashboard has it
    private var medianGap: String? {
        let starts = updates.compactMap(\.startDate).sorted()
        guard starts.count > 1 else { return nil }
        let gaps = zip(starts, starts.dropFirst()).map { $1.timeIntervalSince($0) }.sorted()
        let middle = gaps.count / 2
        let median = gaps.count % 2 == 0 ? (gaps[middle - 1] + gaps[middle]) / 2 : gaps[middle]
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day]
        formatter.unitsStyle = .full
        formatter.calendar = Calendar.current
        formatter.calendar?.locale = .app
        return formatter.string(from: median)
    }

    var body: some View {
        Group {
            if !updates.isEmpty {
                List {
                    Section {
                        LabeledContent(String(localized: "Updates")) {
                            Text(verbatim: "\(updates.count)")
                                .monospacedDigit()
                        }
                        if let medianGap {
                            LabeledContent(String(localized: "Median time between updates")) {
                                Text(verbatim: medianGap)
                                    .monospacedDigit()
                            }
                        }
                    }
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
