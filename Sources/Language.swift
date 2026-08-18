import Foundation

// iOS läser appens språk vid start, så ett byte i inställningarna slår normalt
// igenom först vid nästa körning. Genom att byta klass på Bundle.main till en
// som slår upp i det valda .lproj gäller valet direkt i stället.
enum AppLanguage {
    private(set) static var override: Bundle?

    static func apply(_ code: String) {
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
