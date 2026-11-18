#if os(macOS)
import SwiftUI
import AppKit
import BraidCore

@main
struct BraidArtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model=AppModel()

    init() {
        if let identifier = Bundle.main.bundleIdentifier {
            Self.migratePreferences(defaults: .standard, from: "org.braidart.mac", to: identifier)
        }
    }

    static func migratePreferences(defaults: UserDefaults, from previousIdentifier: String, to identifier: String) {
        let migrationKey = "hasMigratedMacBundlePreferences"
        let current = defaults.persistentDomain(forName: identifier) ?? [:]
        guard identifier != previousIdentifier, current[migrationKey] as? Bool != true else { return }

        let previous = defaults.persistentDomain(forName: previousIdentifier) ?? [:]
        for key in [AppModel.customDimensionsKey, FirstLaunchHelp.preferenceKey] where current[key] == nil {
            if let value = previous[key] {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: migrationKey)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model:model)
                .frame(minWidth:1050,minHeight:720)
                .onOpenURL { model.open(url:$0) }
                .task {
                    FirstLaunchHelp.showIfNeeded { delegate.showHelp(nil) }
                }
        }
        .defaultSize(width:1320,height:900)
        .commands {
            AboutMenuCommands()
            HelpMenuCommands(showHelp:{ delegate.showHelp(nil) })
            CommandGroup(replacing:.newItem) {
                Button(L("Open…")) { model.chooseImage() }.keyboardShortcut("o").disabled(model.busy)
                Button(L("Open from Photos…"), action: model.choosePhoto).disabled(model.busy)
            }
            CommandGroup(replacing:.saveItem) {
                Divider()
                Button(L("Close")) { NSApp.sendAction(#selector(NSWindow.performClose(_:)),to:nil,from:nil) }.keyboardShortcut("w")
                Button(L("Save…")) { model.saveProject() }.keyboardShortcut("s").disabled(model.project == nil || model.busy)
                Menu(L("Export")) {
                    Button(L("Result as PNG…")) { model.exportPNG() }.disabled(model.project == nil || model.busy)
                    Button(L("3D View as PNG…")) { model.export3DPicture() }.disabled(model.selectedTab != 3 || model.curves == nil || model.busy)
                    Button(L("Vector PDF…")) { model.exportPDF() }.disabled(model.curves == nil || model.busy)
                    Button(L("3D Object (GLB)…")) { model.exportGLB() }.disabled(model.curves == nil || model.busy)
                    Button(L("3D Object (USDZ)…")) { model.exportUSDZ() }.disabled(model.curves == nil || model.busy)
                    Button(L("Solution and Tile Data…")) { model.exportData() }.disabled(model.project == nil || model.busy)
                }
            }
        }
        Window(L("About BraidArt"),id:"about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}


struct HelpMenuCommands: Commands {
    let showHelp:()->Void
    var body: some Commands {
        CommandGroup(replacing:.help) {
            Button(L("BraidArt Help"),action:showHelp).keyboardShortcut("?",modifiers:.command)
        }
    }
}

struct AboutMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing:.appInfo) {
            Button(L("About BraidArt")) { openWindow(id:"about") }
        }
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var helpWindow:NSWindow?
    private let helpNavigation=HelpNavigation()
    private let systemHelpMenu=NSMenu(title:L("Help"))
    private var helpSearchResults=[NSMenuItem]()
    private lazy var nativeHelpMenu:NSMenu = {
        let menu=NSMenu(title:L("Help"))
        menu.autoenablesItems=false
        let searchView=NSView(frame:NSRect(x:0,y:0,width:320,height:34))
        let label=NSTextField(labelWithString:L("Search"))
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(x:14,y:9))
        let searchX=label.frame.maxX+8
        let search=NSSearchField(frame:NSRect(x:searchX,y:5,width:306-searchX,height:24))
        search.setAccessibilityLabel(L("Search BraidArt Help"))
        search.sendsSearchStringImmediately=true
        search.target=self;search.action=#selector(searchHelp(_:))
        searchView.addSubview(label);searchView.addSubview(search)
        let searchItem=NSMenuItem();searchItem.view=searchView
        menu.addItem(searchItem);menu.addItem(.separator())
        let item=NSMenuItem(title:L("BraidArt Help"),action:#selector(showHelp(_:)),keyEquivalent:"?")
        item.target=self;item.keyEquivalentModifierMask=[.command]
        menu.addItem(item)
        return menu
    }()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage=AppIcon.image
        NSApp.dockTile.display()
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationDidUpdate(_ notification:Notification) {
        // A native search field searches the short introduction and opens its matching section.
        guard let item=NSApp.mainMenu?.items.first(where: { $0.title==L("Help") }),
              item.submenu !== nativeHelpMenu else { return }
        item.submenu=nativeHelpMenu
        // The visible menu supplies its own topic search, so suppress a second system field.
        NSApp.helpMenu=systemHelpMenu
    }
    @objc func showHelp(_ sender:Any?) {
        openHelp(at:.overview)
    }
    @objc private func searchHelp(_ sender:NSSearchField) {
        for item in helpSearchResults { nativeHelpMenu.removeItem(item) }
        helpSearchResults=[]
        let query=sender.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        if !query.isEmpty {
            for topic in HelpTopic.matching(query) {
                let item=NSMenuItem(title:topic.title,action:#selector(showHelpTopic(_:)),keyEquivalent:"")
                item.target=self;item.representedObject=topic.rawValue
                helpSearchResults.append(item)
            }
            if helpSearchResults.isEmpty {
                let item=NSMenuItem(title:L("No Help Topics Found"),action:nil,keyEquivalent:"")
                item.isEnabled=false;helpSearchResults=[item]
            }
        }
        for (index,item) in helpSearchResults.enumerated() { nativeHelpMenu.insertItem(item,at:index+1) }
    }
    @objc private func showHelpTopic(_ sender:NSMenuItem) {
        guard let name=sender.representedObject as? String,let topic=HelpTopic(rawValue:name) else { return }
        openHelp(at:topic)
    }
    private func openHelp(at topic:HelpTopic) {
        if helpWindow == nil {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:860,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title=L("BraidArt Help");window.minSize=NSSize(width:720,height:580)
            window.contentView=NSHostingView(rootView:HelpView(navigation:helpNavigation))
            window.isReleasedWhenClosed=false;window.center()
            window.setFrameAutosaveName("BraidArtHelp")
            helpWindow=window
        }
        helpNavigation.show(topic)
        helpWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication)->Bool { true }
}

#endif
