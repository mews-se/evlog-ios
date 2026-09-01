import SwiftUI
import UIKit

struct AboutView: View {
    private static let developer = "Martin Stockzell (mews-se)"

    // the icon exactly as shipped, read from the bundle so the page never drifts
    // from the home screen. the catalog compiles it under the names listed in
    // CFBundleIcons - asking for "AppIcon" itself comes back empty
    private static let appIcon: UIImage? = {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return UIImage(named: name)
    }()

    @AppStorage(Pref.tessieToken.key) private var tessieToken = Pref.tessieToken.value

    @State private var iconTaps = 0
    @State private var lastIconTap = Date.distantPast
    @State private var iconOffset: CGFloat = 0
    @State private var iconTilt: Double = 0
    @State private var trailOpacity: Double = 0
    @State private var plaidness: Double = 0
    @State private var launching = false

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
                    // 60 points is the compiled variant's own size - larger would upscale
                    if let icon = Self.appIcon {
                        Image(uiImage: icon)
                            .resizable()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                            .rotationEffect(.degrees(iconTilt))
                            .offset(x: iconOffset)
                            // the background takes no part in layout, so the rows below
                            // stand still; placed after offset it stays anchored to the frame
                            .background {
                                ZStack {
                                    Capsule()
                                        .fill(LinearGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple],
                                                             startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(iconOffset, 0), height: 12)
                                        .blur(radius: 3)
                                        .opacity(trailOpacity * (1 - plaidness))
                                    Plaid()
                                        .frame(width: max(iconOffset, 0), height: 12 + 52 * plaidness)
                                        .clipShape(Capsule())
                                        .blur(radius: 2)
                                        .opacity(trailOpacity * plaidness)
                                }
                                .offset(x: iconOffset / 2)
                            }
                            .padding(.bottom, 6)
                            .onTapGesture { iconTapped() }
                    }
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
                        title: String(localized: "Source code"), detail: "GitHub",
                        url: "https://github.com/mews-se/evlog-ios")

                LabeledContent {
                    Text(verbatim: "MIT")
                } label: {
                    Label(String(localized: "License"), systemImage: "doc.plaintext")
                }

                LinkRow(icon: "gift",
                        title: String(localized: "Donate"),
                        detail: String(localized: "If you feel like giving back"),
                        url: "https://mews-se.github.io/evlog-site/donate/")
            } header: {
                Text("Open source")
            } footer: {
                Text("The code is there to read, build and change.")
            }

            Section {
                LinkRow(icon: "car.fill", title: "TeslaMate",
                        detail: String(localized: "Drives, charges and vehicle data"),
                        url: "https://github.com/teslamate-org/teslamate")
                LinkRow(icon: "bolt.fill", title: "supercharge.info",
                        detail: String(localized: "Supercharger locations"),
                        url: "https://supercharge.info")
                LinkRow(icon: "doc.text", title: "notateslaapp.com",
                        detail: String(localized: "Software release notes"),
                        url: "https://www.notateslaapp.com")
                if !tessieToken.isEmpty {
                    LinkRow(icon: "creditcard", title: "Tessie",
                            detail: String(localized: "Charging costs TeslaMate lacks"),
                            url: "https://tessie.com")
                }
            } header: {
                Text("Data sources")
            } footer: {
                Text(verbatim: "This app is an unofficial community tool and is not affiliated with, endorsed by, or supported by the official TeslaMate project.")
            }
        }
        // the list's default first-section margin leaves a hole between the bar
        // and the icon; the page reads better with the header pulled up
        .contentMargins(.top, 8, for: .scrollContent)
        .navigationTitle("About EVLog")
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }

    private func iconTapped() {
        let now = Date()
        if now.timeIntervalSince(lastIconTap) > 1.5 { iconTaps = 0 }
        lastIconTap = now
        iconTaps += 1
        guard iconTaps >= 5, !launching else { return }
        iconTaps = 0
        launching = true
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            trailOpacity = 1
            plaidness = 0
            withAnimation(.easeIn(duration: 0.12)) { iconTilt = -10 }
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.easeIn(duration: 0.45)) { iconOffset = 600 }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.25)) { plaidness = 1 }
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.easeOut(duration: 0.35)) { trailOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(400))
            iconTilt = 6
            iconOffset = -600
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) { iconOffset = 0 }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.2)) { iconTilt = 0 }
            try? await Task.sleep(for: .milliseconds(300))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            launching = false
        }
    }
}

// horizontal bands crossed with the same bands at half strength
private struct Plaid: View {
    private static let bands: [(Color, CGFloat)] = [
        (.red, 16), (.black, 4), (.green, 12), (.yellow, 3), (.blue, 10), (.black, 4)
    ]

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                for (color, height) in Self.bands {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: height)),
                                 with: .color(color))
                    y += height
                }
            }
            context.opacity = 0.55
            var x: CGFloat = 0
            while x < size.width {
                for (color, width) in Self.bands {
                    context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)),
                                 with: .color(color))
                    x += width
                }
            }
        }
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
