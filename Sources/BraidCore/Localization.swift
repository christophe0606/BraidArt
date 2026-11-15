import Foundation

/// App and core messages share the package's standard Localizable.strings table.
/// Bundle selects French when supported by the Mac's language preferences, and
/// uses the English development localization for all other languages.
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    let text=NSLocalizedString(key,bundle:.module,comment:"")
    return arguments.isEmpty ? text : String(format:text,locale:Locale.current,arguments:arguments)
}
