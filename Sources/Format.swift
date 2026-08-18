import Foundation
import SwiftUI

enum Fmt {
    static func km(_ value: Double?, decimals: Int = 1) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(decimals))) + " km"
    }

    static func kwh(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(1))) + " kWh"
    }

    static func kr(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0))) + " kr"
    }

    static func temp(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0))) + "°"
    }

    static func kw(_ value: Double?) -> String {
        guard let value else { return "–" }
        let decimals = value < 10 ? 1 : 0
        return value.formatted(.number.precision(.fractionLength(decimals))) + " kW"
    }

    static func consumption(_ whPerKm: Double?) -> String {
        guard let whPerKm else { return "–" }
        return whPerKm.formatted(.number.precision(.fractionLength(0))) + " Wh/km"
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "–" }
        return (fraction * 100).formatted(.number.precision(.fractionLength(0))) + " %"
    }

    static func number(_ value: Double?, decimals: Int = 2) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(decimals)))
    }

    static func pct(_ value: Double?, decimals: Int = 1) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(decimals))) + " %"
    }

    static func duration(_ minutes: Double?) -> String {
        guard let minutes else { return "–" }
        let m = Int(minutes)
        return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(.dateTime.hour().minute())
    }

    static func day(_ date: Date?) -> String {
        guard let date else { return "–" }
        if Calendar.current.isDateInToday(date) { return String(localized: "Today", bundle: .current) }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Yesterday", bundle: .current) }
        // bara första bokstaven - .capitalized skulle versalisera månaden mitt i frasen
        let s = date.formatted(.dateTime.weekday(.wide).day().month())
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    // "12 → 80 %", nil när nivåerna saknas så listraderna kan hoppa över etiketten
    static func battery(_ details: DriveBattery?) -> String? {
        guard let start = details?.startBatteryLevel, let end = details?.endBatteryLevel else { return nil }
        return "\(start) → \(end) %"
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(.dateTime.year().month().day())
    }

    static func since(_ date: Date?) -> String {
        guard let date else { return "–" }
        if Calendar.current.isDateInToday(date) { return time(date) }
        return date.formatted(.dateTime.day().month().hour().minute())
    }
}

enum CarState {
    static func label(_ state: String?, charging: String?) -> (text: String, color: Color, icon: String) {
        if charging == "Charging" { return (String(localized: "Charging", bundle: .current), .green, "bolt.fill") }
        switch state {
        case "driving": return (String(localized: "Driving", bundle: .current), .blue, "steeringwheel")
        case "charging": return (String(localized: "Charging", bundle: .current), .green, "bolt.fill")
        case "online": return (String(localized: "Online", bundle: .current), .primary, "car.fill")
        case "asleep": return (String(localized: "Asleep", bundle: .current), .secondary, "moon.zzz.fill")
        case "suspended": return (String(localized: "Falling asleep", bundle: .current), .secondary, "moon.fill")
        case "offline": return (String(localized: "Offline", bundle: .current), .orange, "antenna.radiowaves.left.and.right.slash")
        case "updating": return (String(localized: "Updating", bundle: .current), .purple, "arrow.down.circle.fill")
        default: return (state ?? String(localized: "Unknown", bundle: .current), .secondary, "questionmark.circle")
        }
    }

    // TeslaMates skala: 100 % är rated förbrukning, högre är bättre
    static func efficiencyColor(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        // avrunda som visningen gör, annars ser ett utskrivet "100 %" gult ut
        let shown = percent.rounded()
        if shown >= 100 { return .green }
        if shown >= 85 { return .yellow }
        return .red
    }

    static func batteryColor(_ level: Int?) -> Color {
        guard let level else { return .gray }
        if level <= 15 { return .red }
        if level <= 30 { return .orange }
        return .green
    }
}
