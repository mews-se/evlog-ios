import Foundation

// the app speaks english only. the region still owns numbers, dates and units -
// an english app on a swedish phone keeps swedish formats
extension Locale {
    static var app: Locale {
        guard let region = Locale.current.region?.identifier else {
            return Locale(identifier: "en")
        }
        return Locale(identifier: "en_\(region)")
    }
}
