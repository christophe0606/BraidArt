import SwiftUI
import BraidCore

/// Only values displayed by the sidebar participate in its update boundary.
/// New preview pixels, status messages and solver progress do not rebuild it.
struct SidebarState: Equatable {
    let settings: BraidCore.Settings
    let palette: [PaletteEntry]
    let sourceName: String
    let hasSourceImage: Bool
    let hasCropSelection: Bool
    let preparedSize: CGSize?
    let hasProject: Bool
    let solverURL: URL?
    let paletteCount: Int
    let paletteSeparation: PaletteSeparation
    let paletteIncludeAccents: Bool
    let exportTileSize: Int
    let blocksEditing: Bool

    @MainActor init(model: AppModel) {
        settings=model.settings;palette=model.paletteEntries;sourceName=model.sourceName
        hasSourceImage=model.sourceImage != nil
        hasCropSelection=model.hasCropSelection
        preparedSize=model.prepared.map { CGSize(width:$0.width,height:$0.height) }
        hasProject=model.project != nil;solverURL=model.solverURL
        paletteCount=model.paletteCount;paletteSeparation=model.paletteSeparation
        paletteIncludeAccents=model.paletteIncludeAccents;exportTileSize=model.exportTileSize
        blocksEditing=model.blocksEditing
    }
}

/// Keep the model unobserved here: ContentView supplies a value snapshot so that
/// unrelated model publications cannot invalidate the native sidebar controls.
struct SettingsSidebar: View, Equatable {
    let model: AppModel
    let state: SidebarState
    static func == (lhs:Self,rhs:Self)->Bool { lhs.model === rhs.model && lhs.state == rhs.state }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack(spacing:10) {
                    Image(nsImage:AppIcon.image).resizable().interpolation(.low).frame(width:40,height:40).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:2) { Text("BraidArt").font(.title2.bold());Text("IMAGE TO WOVEN TILES").font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(1.5).foregroundStyle(.secondary) }
                }.padding(.bottom,6)
                section("01", "Picture") {
                    Button(action:model.chooseImage) { Label("Open Image or Project…",systemImage:"photo.on.rectangle") }.controlSize(.large).frame(maxWidth:.infinity)
                    Text("Or drop an image anywhere in this window.").font(.caption).foregroundStyle(.secondary)
                    if !state.sourceName.isEmpty { Text(state.sourceName).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    Stepper("Image width: \(state.settings.columns) tiles",value:binding(\.settings.columns),in:8...256,step:2).disabled(!state.hasSourceImage)
                    if let size=state.preparedSize { Text("\(Int(size.width)) × \(Int(size.height)) = \(Int(size.width*size.height)) tiles").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    Toggle("Luminance only",isOn:binding(\.settings.grayscale)).disabled(!state.hasSourceImage)
                    slider("Contrast",value:binding(\.settings.contrast),in:0.25...3,resetTo:BraidCore.Settings().contrast).disabled(!state.hasSourceImage)
                    slider("Brightness",value:binding(\.settings.brightness),in:-0.5...0.5,resetTo:BraidCore.Settings().brightness).disabled(!state.hasSourceImage)
                    if state.hasSourceImage {
                        ColorPicker("Transparent areas",selection:colorBinding(\.alphaBackground),supportsOpacity:false)
                        Button("Delete Crop",action:model.clearCrop).font(.caption).disabled(!state.hasCropSelection)
                    } else if state.hasProject {
                        Text("This project contains the sampled image. Open the original picture to change the crop or resize.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                section("02", "Tiles & palette") {
                    ColorPicker("Background",selection:colorBinding(\.background),supportsOpacity:false)
                    ForEach(state.palette) { entry in
                        HStack {
                            ColorPicker("Strand \(entry.index+1)",selection:model.paletteColorBinding(for:entry),supportsOpacity:false)
                            if state.settings.palette.count>1 { Button { model.removePaletteColor(entry) } label:{Image(systemName:"minus.circle")}.buttonStyle(.plain).foregroundStyle(.secondary).help("Remove strand color") }
                        }
                    }
                    HStack {
                        Button("Black & White") { model.replacePalette([.black,.white]) }
                        Spacer()
                        Button { if state.settings.palette.count<8 { model.settings.palette.append(RGB(Double.random(in:0...1),Double.random(in:0...1),Double.random(in:0...1))) } } label:{Image(systemName:"plus")}.disabled(state.settings.palette.count>=8).help("Add strand color")
                    }
                    HStack {
                        Stepper("Up to \(state.paletteCount) colors",value:binding(\.paletteCount),in:2...8)
                        Button("Extract",action:model.extractPalette).disabled(state.preparedSize==nil).help("Extract strand colors and fit the background to the prepared picture")
                    }
                    Picker("Color separation",selection:binding(\.paletteSeparation)) {
                        ForEach(PaletteSeparation.allCases) { separation in Text(separation.rawValue).tag(separation) }
                    }.help("Higher separation merges more similar shades. Select Extract to apply it.")
                    VStack(alignment:.leading,spacing:4) {
                        HStack {
                            Text("Background contrast")
                            Spacer()
                            Text(String(format:"%.0f",state.settings.backgroundMinimumDistance)).monospacedDigit().foregroundStyle(.secondary)
                        }.font(.caption)
                        HStack(spacing:8) {
                            Slider(value:binding(\.settings.backgroundMinimumDistance),in:1...50,step:1)
                                .accessibilityLabel("Background contrast")
                            Button("Reset") { model.settings.backgroundMinimumDistance=BraidCore.Settings.defaultBackgroundMinimumDistance }
                                .controlSize(.small).accessibilityLabel("Reset background contrast")
                        }
                        Text("Higher values make strands stand out more. Select Extract to apply.").font(.caption).foregroundStyle(.secondary)
                    }.help("Minimum perceptual distance (CIEDE2000) between the extracted background and every strand. Default: 15.")
                    Toggle("Include small accents",isOn:binding(\.paletteIncludeAccents)).help("Preserve distinct colors in small details using a more detailed sample of the crop. Turn off to favor the largest image regions.")
                    Text("Higher separation avoids similar shades and may return fewer colors. Use 6–8 colors to include more details. Select Extract to apply.").font(.caption).foregroundStyle(.secondary)
                    Text("Extract keeps the background distinct from every strand so they remain visible. It may use fewer strand colors when needed. Luminance mode selects shades from black to white.").font(.caption).foregroundStyle(.secondary)
                    Text("\(state.settings.palette.count*state.settings.palette.count*4) dark tiles · four strand geometries").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Strand geometry") {
                        VStack(spacing:8) {
                            slider("Width",value:binding(\.settings.strandWidth),in:0.1...min(0.6,0.98-state.settings.gap))
                            slider("Crossing gap",value:binding(\.settings.gap),in:0...min(0.6,0.98-state.settings.strandWidth))
                            Text("Defaults match the notebook: width 0.414, gap 0.4.").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.top,8)
                    }
                }
                section("03", "Partition solve") {
                    Stepper("Part size: \(state.settings.partitionSize) × \(state.settings.partitionSize)",value:binding(\.settings.partitionSize),in:1...20)
                    Picker("Time per part",selection:binding(\.settings.secondsPerPartition)) {
                        Text("5 seconds").tag(5.0);Text("30 seconds").tag(30.0);Text("2 minutes").tag(120.0);Text("10 minutes").tag(600.0)
                    }
                    Picker("Optimality gap",selection:binding(\.settings.relativeGap)) {
                        Text("Exact (0%)").tag(0.0);Text("1%").tag(0.01);Text("5%").tag(0.05)
                    }
                    Stepper("CPU threads: \(state.settings.threads)",value:binding(\.settings.threads),in:1...16)
                    Text("Parts preserve strand colors along their top and left neighbors. Smaller parts solve faster.").font(.caption).foregroundStyle(.secondary)
                    if state.solverURL == nil {
                        Label("Bundled solver unavailable",systemImage:"exclamationmark.triangle").foregroundStyle(.orange)
                        Text("Reinstall BraidArt to restore its bundled solver.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                section("04", "Save & export") {
                    Picker("PNG tile size",selection:binding(\.exportTileSize)) {
                        Text("20 px").tag(20);Text("50 px").tag(50);Text("100 px").tag(100)
                    }
                    Button("Save Project…",action:model.saveProject).disabled(!state.hasProject)
                    Text("Choose File → Export for all export formats.").font(.caption).foregroundStyle(.secondary)
                    Text("Data export includes JSON, Wolfram data and tile images for subsequent processing.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(22).disabled(state.blocksEditing)
        }.frame(minWidth:290,idealWidth:320,maxWidth:370)
            .background(Color(nsColor:.controlBackgroundColor))
    }
    private func binding<Value>(_ path: ReferenceWritableKeyPath<AppModel,Value>)->Binding<Value> {
        Binding(get:{model[keyPath:path]},set:{model[keyPath:path]=$0})
    }
    private func colorBinding(_ path: WritableKeyPath<BraidCore.Settings,RGB>)->Binding<Color> { Binding(get:{model.settings[keyPath:path].color},set:{model.settings[keyPath:path]=RGB(color:$0)}) }
    private func section<C:View>(_ number: String,_ text: String,@ViewBuilder content:()->C)->some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text(number).font(.caption.monospaced().weight(.semibold)).foregroundStyle(.orange);Text(text).font(.headline) }
            content()
        }
    }
    private func slider(_ label: String,value: Binding<Double>,in range: ClosedRange<Double>,resetTo defaultValue:Double?=nil)->some View {
        VStack(alignment:.leading,spacing:4) {
            HStack { Text(label);Spacer();Text(String(format:"%.3f",value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            HStack(spacing:8) {
                Slider(value:value,in:range)
                if let defaultValue {
                    Button("Reset") { value.wrappedValue=defaultValue }
                        .controlSize(.small)
                        .accessibilityLabel("Reset \(label.lowercased())")
                        .help("Reset \(label.lowercased()) to \(String(format:"%g",defaultValue))")
                }
            }
        }
    }
}
