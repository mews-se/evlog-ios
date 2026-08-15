import Foundation
import SwiftUI

enum Fmt {
    static let sv = Locale(identifier: "sv_SE")

    static func km(_ value: Double?, decimals: Int = 1) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(decimals)).locale(sv)) + " km"
    }

    static func kwh(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(1)).locale(sv)) + " kWh"
    }

    static func kr(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0)).locale(sv)) + " kr"
    }

    static func temp(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0)).locale(sv)) + "°"
    }

    static func kw(_ value: Double?) -> String {
        guard let value else { return "–" }
        let decimals = value < 10 ? 1 : 0
        return value.formatted(.number.precision(.fractionLength(decimals)).locale(sv)) + " kW"
    }

    static func consumption(_ whPerKm: Double?) -> String {
        guard let whPerKm else { return "–" }
        return whPerKm.formatted(.number.precision(.fractionLength(0)).locale(sv)) + " Wh/km"
    }

    static func duration(_ minutes: Double?) -> String {
        guard let minutes else { return "–" }
        let m = Int(minutes)
        return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(.dateTime.hour().minute().locale(sv))
    }

    static func day(_ date: Date?) -> String {
        guard let date else { return "–" }
        if Calendar.current.isDateInToday(date) { return "Idag" }
        if Calendar.current.isDateInYesterday(date) { return "Igår" }
        return date.formatted(.dateTime.weekday(.wide).day().month().locale(sv)).capitalized
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "–" }
        let f = RelativeDateTimeFormatter()
        f.locale = sv
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }
}

enum CarState {
    static func label(_ state: String?, charging: String?) -> (text: String, color: Color, icon: String) {
        if charging == "Charging" { return ("Laddar", .green, "bolt.fill") }
        switch state {
        case "driving": return ("Kör", .blue, "steeringwheel")
        case "charging": return ("Laddar", .green, "bolt.fill")
        case "online": return ("Online", .primary, "car.fill")
        case "asleep": return ("Sover", .secondary, "moon.zzz.fill")
        case "suspended": return ("Vilar", .secondary, "moon.fill")
        case "offline": return ("Offline", .orange, "antenna.radiowaves.left.and.right.slash")
        case "updating": return ("Uppdaterar", .purple, "arrow.down.circle.fill")
        default: return (state ?? "Okänd", .secondary, "questionmark.circle")
        }
    }

    static func batteryColor(_ level: Int?) -> Color {
        guard let level else { return .gray }
        if level <= 15 { return .red }
        if level <= 30 { return .orange }
        return .green
    }
}
