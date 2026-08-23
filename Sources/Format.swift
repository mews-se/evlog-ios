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

    // regen is under 1 kWh on nine drives in ten, where one decimal of kWh hides more than it shows
    static func energy(_ kwh: Double?) -> String {
        guard let kwh else { return "–" }
        if abs(kwh) < 1 {
            return (kwh * 1000).formatted(.number.precision(.fractionLength(0))) + " Wh"
        }
        return kwh.formatted(.number.precision(.fractionLength(1))) + " kWh"
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
        // the year only when it is not this one - a list going back far enough would
        // otherwise show two Decembers with nothing to tell them apart
        let s = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(.dateTime.weekday(.wide).day().month().locale(.app))
            : date.formatted(.dateTime.weekday(.wide).day().month().year().locale(.app))
        // first letter only - .capitalized would capitalise the month mid-phrase too
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    // "12 → 80 %", nil when the levels are missing so list rows can skip the label
    static func battery(_ details: DriveBattery?) -> String? {
        guard let start = details?.startBatteryLevel, let end = details?.endBatteryLevel else { return nil }
        return "\(start) → \(end) %"
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(.dateTime.year().month().day().locale(.app))
    }

    // the year only when it is not this one
    static func shortDate(_ date: Date) -> String {
        if Calendar.current.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month().locale(.app))
        }
        return self.date(date)
    }

    static func since(_ date: Date?) -> String {
        guard let date else { return "–" }
        if Calendar.current.isDateInToday(date) { return time(date) }
        return date.formatted(.dateTime.day().month().hour().minute().locale(.app))
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
        // newer cars report offline whenever they sleep, so from the outside it is the same
        // rest as asleep and wears the same moon. the word stays TeslaMate's
        case "offline": return (String(localized: "Offline", bundle: .current), .secondary, "moon.zzz.fill")
        case "updating": return (String(localized: "Updating", bundle: .current), .purple, "arrow.down.circle.fill")
        default: return (state ?? String(localized: "Unknown", bundle: .current), .secondary, "questionmark.circle")
        }
    }

    // TeslaMate's scale: 100 % is rated consumption, higher is better
    static func efficiencyColor(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        // round as the display does, otherwise a printed "90 %" comes out yellow
        let shown = percent.rounded()
        if shown >= 90 { return .green }
        if shown >= 71 { return .yellow }
        return .red
    }

    static func batteryColor(_ level: Int?) -> Color {
        guard let level else { return .gray }
        if level <= 15 { return .red }
        if level <= 30 { return .orange }
        return .green
    }
}
