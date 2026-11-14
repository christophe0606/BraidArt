import AppKit

/// The same artwork is used for Swift package launches, the Dock and About.
@MainActor
enum AppIcon {
    static let image: NSImage = {
        if let url=Bundle.module.url(forResource:"AppIcon",withExtension:"icns"),
           let image=NSImage(contentsOf:url) {
            return image
        }
        return NSImage(systemSymbolName:"circle.hexagongrid.fill",accessibilityDescription:"BraidArt") ?? NSImage(size:NSSize(width:128,height:128))
    }()
}
