import Foundation

// the app speaks whatever language it is running in, but the region still owns
// numbers, dates, units and currency - a chinese app on a swedish phone keeps
// swedish formats
extension Locale {
    static var app: Locale {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        guard let region = Locale.current.region?.identifier else {
            return Locale(identifier: language)
        }
        return Locale(identifier: "\(language)_\(region)")
    }
}
