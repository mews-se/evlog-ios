import Foundation

// iOS reads the app's language at launch, so a change in settings would normally
// take until the next run. Swapping the class of Bundle.main for one that looks up
// the chosen .lproj makes the choice apply straight away instead.
enum AppLanguage {
    private(set) static var override: Bundle?
    private(set) static var code = Pref.language.value

    static func apply(_ code: String) {
        Self.code = code
        object_setClass(Bundle.main, LocalizedBundle.self)
        override = code == "system"
            ? nil
            : Bundle.main.path(forResource: code, ofType: "lproj").flatMap { Bundle(path: $0) }
    }
}

private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table: String?) -> String {
        AppLanguage.override?.localizedString(forKey: key, value: value, table: table)
            ?? super.localizedString(forKey: key, value: value, table: table)
    }
}

// String(localized:) reads the bundle past localizedString(forKey:value:table:) and
// so misses the class swap above. The calls pass .current instead, which follows the
// language choice at once rather than at the next launch.
extension Bundle {
    static var current: Bundle { AppLanguage.override ?? .main }
}

// views get the language's locale through .environment(\.locale,), but model code
// sits outside it and would otherwise read the system language instead of the app's.
// the region is kept: picking a language should change weekdays and months, not
// rework numbers and currency for someone who still lives where they lived
extension Locale {
    static var app: Locale {
        guard AppLanguage.code != "system" else { return .current }
        guard let region = Locale.current.region?.identifier else {
            return Locale(identifier: AppLanguage.code)
        }
        return Locale(identifier: "\(AppLanguage.code)_\(region)")
    }
}
