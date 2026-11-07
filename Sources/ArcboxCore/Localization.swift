import Foundation

public enum AppLanguage {
    public static var code: String {
        let selected = UserDefaults.standard.string(forKey: "language") ?? "en"
        if selected == "ru" || selected == "en" { return selected }
        return Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en"
    }
    public static var locale: Locale { Locale(identifier: code) }
    private static let resources: Bundle = {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let packaged = executable.deletingLastPathComponent().appendingPathComponent("../Resources/Arcbox_ArcboxCore.bundle").standardizedFileURL
        return Bundle(url: packaged) ?? Bundle.module
    }()
    public static func text(_ key: String) -> String {
        guard let path = resources.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

public func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLanguage.text(key)
    return arguments.isEmpty ? format : String(format: format, locale: AppLanguage.locale, arguments: arguments)
}
