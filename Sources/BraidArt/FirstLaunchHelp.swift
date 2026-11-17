import Foundation

@MainActor
enum FirstLaunchHelp {
    static let preferenceKey="hasShownFirstLaunchHelp"

    static func showIfNeeded(defaults:UserDefaults = .standard,showHelp:()->Void) {
        guard !defaults.bool(forKey:preferenceKey) else { return }
        defaults.set(true,forKey:preferenceKey)
        showHelp()
    }
}
