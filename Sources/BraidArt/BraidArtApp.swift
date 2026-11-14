import SwiftUI
import AppKit
import BraidCore

@main
struct BraidArtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model=AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model:model)
                .frame(minWidth:1050,minHeight:720)
                .onOpenURL { model.open(url:$0) }
        }
        .defaultSize(width:1320,height:900)
        .commands {
            AboutMenuCommands()
            CommandGroup(replacing:.newItem) {
                Button("Open Image or Project…") { model.chooseImage() }.keyboardShortcut("o")
                Button("Save Project…") { model.saveProject() }.keyboardShortcut("s").disabled(model.project == nil || model.busy)
            }
            CommandGroup(after:.importExport) {
                Button("Export Result as PNG…") { model.exportPNG() }.disabled(model.project == nil || model.busy)
                Button("Export Solution and Tile Data…") { model.exportData() }.disabled(model.project == nil || model.busy)
            }
        }
        Window("About BraidArt",id:"about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

struct AboutMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing:.appInfo) {
            Button("About BraidArt") { openWindow(id:"about") }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage=AppIcon.image
        NSApp.dockTile.display()
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication)->Bool { true }
}
