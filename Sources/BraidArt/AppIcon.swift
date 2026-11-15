import AppKit

/// Shared artwork for the Dock, sidebar, About, Help and Finder documents.
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
