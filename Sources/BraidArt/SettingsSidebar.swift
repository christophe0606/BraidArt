import SwiftUI
import BraidCore

/// Only values displayed by the sidebar participate in its update boundary.
/// New preview pixels, status messages and solver progress do not rebuild it.
struct SidebarState: Equatable {
    let settings: BraidCore.Settings
    let customDimensions:[PictureExportSize]
    let palette: [PaletteEntry]
    let sourceName: String
    let hasSourceImage: Bool
    let canChangeOutputDimensions: Bool
    let hasCropSelection: Bool
    let preparedSize: CGSize?
    let hasProject: Bool
    let pngSize: CGSize
    let paletteCount: Int
    let paletteSeparation: PaletteSeparation
    let paletteIncludeAccents: Bool
    let blocksEditing: Bool

    @MainActor init(model: AppModel) {
        settings=model.settings;palette=model.paletteEntries;sourceName=model.sourceName
        customDimensions=model.customDimensions
        hasSourceImage=model.sourceImage != nil
        canChangeOutputDimensions=model.canChangeOutputDimensions
        hasCropSelection=model.hasCropSelection
        preparedSize=model.prepared.map { CGSize(width:$0.width,height:$0.height) }
        hasProject=model.project != nil
        pngSize=model.project?.settings.outputPixelSize ?? model.settings.outputPixelSize
        paletteCount=model.paletteCount;paletteSeparation=model.paletteSeparation
        paletteIncludeAccents=model.paletteIncludeAccents
        blocksEditing=model.blocksEditing
    }
}

/// Keep the model unobserved here: ContentView supplies a value snapshot so that
/// unrelated model publications cannot invalidate the native sidebar controls.
struct SettingsSidebar: View, Equatable {
    let model: AppModel
    let state: SidebarState
    let showsOutputDimensions: Bool
    static func == (lhs:Self,rhs:Self)->Bool {
        lhs.model === rhs.model && lhs.state == rhs.state && lhs.showsOutputDimensions == rhs.showsOutputDimensions
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack(spacing:10) {
                    Image(platformImage:AppIcon.image).resizable().interpolation(.low).frame(width:40,height:40).clipShape(RoundedRectangle(cornerRadius:8)).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:2) { Text(L("BraidArt")).font(.title2.bold());Text(L("IMAGE TO WOVEN TILES")).font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(1.5).foregroundStyle(.secondary) }
                }.padding(.bottom,6)
                section("01", L("Picture")) {
                    Button(action:model.chooseImage) { Label(L("Open Image, Video or Project…"),systemImage:"photo.on.rectangle") }.controlSize(.large).frame(maxWidth:.infinity)
                    #if os(macOS)
                    Button(action: model.choosePhoto) {
                        Label(L("Open from Photos…"), systemImage: "photo.stack")
                    }
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    Text(L("Or drop an image or video anywhere in this window.")).font(.caption).foregroundStyle(.secondary)
                    #else
                    Text(L("Choose a picture or video from Photos or Files.")).font(.caption).foregroundStyle(.secondary)
                    #endif
                    if !state.sourceName.isEmpty { Text(state.sourceName).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    if showsOutputDimensions {
                        controls.outputDimensions()
                        #if os(iOS)
                            .padding(.bottom,14)
                        #endif
                            .accessibilityIdentifier("sidebarOutputDimensions")
                    }
                    controls.imageWidth
                    controls.luminance
                    if state.hasSourceImage || state.hasProject {
                        Button(L("Reset Crop"),action:model.resetCrop).font(.caption)
                            .disabled(!state.hasSourceImage || !state.hasCropSelection)
                    }
                    if !state.canChangeOutputDimensions {
                        Text(L("This project contains the sampled image. Open the original picture to change the crop or resize.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.vertical,2)
                section("02", L("Tiles & palette")) {
                    controls.palette
                    DisclosureGroup(L("Strand geometry")) {
                        controls.strandGeometry
                            .padding(.top,8)
                    }
                }
                Divider().padding(.vertical,2)
                section("03", L("Partition solve")) {
                    controls.partition
                }
                Divider().padding(.vertical,2)
                section("04", L("Save & export")) {
                    Text(L("%@ × %@ pixels · PNG",String(Int(state.pngSize.width)),String(Int(state.pngSize.height))))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button(L("Save Project…"),action:model.saveProject).disabled(!state.hasProject)
                    #if os(macOS)
                    Text(L("Choose File → Export for all export formats.")).font(.caption).foregroundStyle(.secondary)
                    #else
                    Text(L("Use the export button above to save pictures, videos, PDF and 3D objects.")).font(.caption).foregroundStyle(.secondary)
                    #endif
                    Text(L("Data export includes JSON, Wolfram data and tile images for subsequent processing.")).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(22).disabled(state.blocksEditing)
        }
        #if os(macOS)
        .frame(minWidth:290,idealWidth:320,maxWidth:370)
        .background(Color(nsColor:.controlBackgroundColor))
        #else
        .frame(maxWidth:.infinity)
        .background(Color(uiColor:.secondarySystemBackground))
        #endif
    }
    private var controls: SettingsControls { SettingsControls(model: model, state: state) }

    private func section<C:View>(_ number: String,_ text: String,@ViewBuilder content:()->C)->some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text(number).font(.caption.monospaced().weight(.semibold)).foregroundStyle(.orange);Text(text).font(.headline) }
            content()
        }
    }
}

/// Shared controls for the sidebar and the iPhone settings presentations.
@MainActor
struct SettingsControls {
    let model: AppModel
    let state: SidebarState

    func outputDimensions(compact: Bool = false) -> some View {
        DimensionPicker(title: L("Output dimensions"),
                        selection: Binding(get: { state.settings.outputSize }, set: { model.setOutputSize($0) }),
                        customDimensions: state.customDimensions, compact: compact,
                        onManage: { model.dimensionManagerTarget = .output })
            .disabled(!state.canChangeOutputDimensions)
    }

    var imageWidth: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(L("Image width: %@ tiles", String(describing: state.settings.columns)),value:binding(\.settings.columns),in:8...256,step:2).disabled(!state.hasSourceImage)
                .opacity(state.hasSourceImage ? 1 : 0.65)
                .accessibilityIdentifier("sidebarImageWidth")
            if let size=state.preparedSize { Text(L("%@ × %@ = %@ tiles", String(describing: Int(size.width)), String(describing: Int(size.height)), String(describing: Int(size.width*size.height)))).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            if let size=state.preparedSize {
                Text(String(format:L("Tile size: %.2f × %.2f px"),state.settings.outputPixelSize.width/size.width,state.settings.outputPixelSize.height/size.height))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    var luminance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(L("Luminance only"),isOn:binding(\.settings.grayscale))
            slider(L("Contrast"), value: binding(\.settings.contrast), in: 0.25...3,
                   resetTo: BraidCore.Settings().contrast,
                   onEditingChanged: { model.setToneEditing($0, for: \.contrast) })
            slider(L("Brightness"), value: binding(\.settings.brightness), in: -0.5...0.5,
                   resetTo: BraidCore.Settings().brightness,
                   onEditingChanged: { model.setToneEditing($0, for: \.brightness) })
            if state.hasSourceImage || state.hasProject {
                ColorPicker(L("Transparent areas"),selection:colorBinding(\.alphaBackground),supportsOpacity:false)
            }
        }
        .disabled(!state.hasSourceImage)
        .opacity(state.hasSourceImage ? 1 : 0.65)
    }

    var palette: some View {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker(L("Background"),selection:colorBinding(\.background),supportsOpacity:false)
            ForEach(state.palette) { entry in
                HStack {
                    ColorPicker(L("Strand %@", String(describing: entry.index+1)),selection:model.paletteColorBinding(for:entry),supportsOpacity:false)
                    if state.settings.palette.count>1 { Button { model.removePaletteColor(entry) } label:{Image(systemName:"minus.circle")}.buttonStyle(.plain).foregroundStyle(.secondary).help(L("Remove strand color")) }
                }
            }
            HStack {
                Button(L("Black & White")) { model.replacePalette([.black,.white]) }
                Spacer()
                Button { if state.settings.palette.count<8 { model.settings.palette.append(RGB(Double.random(in:0...1),Double.random(in:0...1),Double.random(in:0...1))) } } label:{Image(systemName:"plus")}.disabled(state.settings.palette.count>=8).help(L("Add strand color"))
            }
            HStack {
                Stepper(L("Up to %@ colors", String(describing: state.paletteCount)),value:binding(\.paletteCount),in:2...8)
                Button(L("Extract"),action:model.extractPalette).disabled(state.preparedSize==nil).help(L("Extract strand colors and fit the background to the prepared picture"))
            }
            Picker(L("Color separation"),selection:binding(\.paletteSeparation)) {
                ForEach(PaletteSeparation.allCases) { separation in Text(separation.title).tag(separation) }
            }.help(L("Higher separation merges more similar shades. Select Extract to apply it."))
            VStack(alignment:.leading,spacing:4) {
                HStack {
                    Text(L("Background contrast"))
                    Spacer()
                    Text(String(format:"%.0f",state.settings.backgroundMinimumDistance)).monospacedDigit().foregroundStyle(.secondary)
                }.font(.caption)
                HStack(spacing:8) {
                    Slider(value:binding(\.settings.backgroundMinimumDistance),in:1...50,step:1)
                        .accessibilityLabel(L("Background contrast"))
                    Button(L("Reset")) { model.settings.backgroundMinimumDistance=BraidCore.Settings.defaultBackgroundMinimumDistance }
                        .controlSize(.small).accessibilityLabel(L("Reset background contrast"))
                }
                Text(L("Higher values make strands stand out more. Select Extract to apply.")).font(.caption).foregroundStyle(.secondary)
            }.help(L("Minimum perceptual distance (CIEDE2000) between the extracted background and every strand. Default: 15."))
            Toggle(L("Include small accents"),isOn:binding(\.paletteIncludeAccents)).help(L("Preserve distinct colors in small details using a more detailed sample of the crop. Turn off to favor the largest image regions."))
            Text(L("Higher separation avoids similar shades and may return fewer colors. Use 6–8 colors to include more details. Select Extract to apply.")).font(.caption).foregroundStyle(.secondary)
            Text(L("Extract keeps the background distinct from every strand so they remain visible. It may use fewer strand colors when needed. Luminance mode selects shades from black to white.")).font(.caption).foregroundStyle(.secondary)
            Text(L("%@ dark tiles · four strand geometries", String(describing: state.settings.palette.count*state.settings.palette.count*4))).font(.caption).foregroundStyle(.secondary)
        }
    }

    var strandGeometry: some View {
        VStack(spacing: 8) {
            slider(L("Width"),value:binding(\.settings.strandWidth),in:0.1...min(0.6,0.98-state.settings.gap))
            slider(L("Crossing gap"),value:binding(\.settings.gap),in:0...min(0.6,0.98-state.settings.strandWidth))
            Text(L("Defaults match the notebook: width 0.414, gap 0.4.")).font(.caption2).foregroundStyle(.secondary)
        }
    }

    var partition: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(L("Part size: %@ × %@", String(describing: state.settings.partitionSize), String(describing: state.settings.partitionSize)),value:binding(\.settings.partitionSize),in:1...20)
            Picker(L("Time per part"),selection:binding(\.settings.secondsPerPartition)) {
                Text(L("5 seconds")).tag(5.0);Text(L("30 seconds")).tag(30.0);Text(L("2 minutes")).tag(120.0);Text(L("10 minutes")).tag(600.0)
            }
            Picker(L("Optimality gap"),selection:binding(\.settings.relativeGap)) {
                Text(L("Exact (0%)")).tag(0.0);Text(L("1%")).tag(0.01);Text(L("5%")).tag(0.05)
            }
            Stepper(L("CPU threads: %@", String(describing: state.settings.threads)),value:binding(\.settings.threads),in:1...16)
            Text(L("Parts preserve strand colors along their top and left neighbors. Smaller parts solve faster.")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func binding<Value>(_ path: ReferenceWritableKeyPath<AppModel,Value>)->Binding<Value> {
        Binding(get:{model[keyPath:path]},set:{model[keyPath:path]=$0})
    }
    private func colorBinding(_ path: WritableKeyPath<BraidCore.Settings,RGB>)->Binding<Color> { Binding(get:{model.settings[keyPath:path].color},set:{model.settings[keyPath:path]=RGB(color:$0)}) }
    private func slider(_ label: String,value: Binding<Double>,in range: ClosedRange<Double>,
                        resetTo defaultValue:Double?=nil,onEditingChanged: @escaping (Bool) -> Void = { _ in })->some View {
        VStack(alignment:.leading,spacing:4) {
            HStack { Text(label);Spacer();Text(String(format:"%.3f",value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            HStack(spacing:8) {
                Slider(value:value,in:range,onEditingChanged:onEditingChanged)
                    .accessibilityLabel(label)
                    .onDisappear { onEditingChanged(false) }
                if let defaultValue {
                    Button(L("Reset")) { value.wrappedValue=defaultValue }
                        .controlSize(.small)
                        .accessibilityLabel(L("Reset %@", String(describing: label.lowercased())))
                        .help(L("Reset %@ to %@", String(describing: label.lowercased()), String(describing: String(format:"%g",defaultValue))))
                }
            }
        }
    }
}
