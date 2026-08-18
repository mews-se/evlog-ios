import Foundation

// iOS läser appens språk vid start, så ett byte i inställningarna slår normalt
// igenom först vid nästa körning. Genom att byta klass på Bundle.main till en
// som slår upp i det valda .lproj gäller valet direkt i stället.
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

// String(localized:) läser bundlen förbi localizedString(forKey:value:table:) och
// missar därför klassbytet ovan. Anropen skickar med .current i stället, så de
// följer språkvalet direkt i stället för först vid nästa start.
extension Bundle {
    static var current: Bundle { AppLanguage.override ?? .main }
}

// vyer får språkets locale via .environment(\.locale,), men modellkod ligger
// utanför den och skulle annars läsa systemets språk i stället för appens
extension Locale {
    static var app: Locale {
        AppLanguage.code == "system" ? .current : Locale(identifier: AppLanguage.code)
    }
}
