import SwiftUI
import BraidCore
import UniformTypeIdentifiers

struct MobileContentView:View {
    private static let initialPanelFraction: CGFloat = 0.38
    @ObservedObject var model:AppModel
    @State private var showingInfo=false
    @State private var showingPhoneSettings = false
    @State private var liveSettings: PhoneLiveSettings?
    @State private var panelFraction = initialPanelFraction
    @GestureState private var panelDrag: CGFloat = 0
    @Namespace private var settingsAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("iPadSidebarWidth") private var sidebarWidth=330.0
    @AppStorage("iPadSidebarVisible") private var sidebarVisible=true
    @State private var sidebarResizeStart:Double?
    private var isPad:Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var isCompactPhone:Bool { !isPad && verticalSizeClass == .compact }
    private var showsCompact3DControls: Bool { isCompactPhone && model.selectedTab == 3 && model.curves != nil }
    private let tabs=[("Prepare","crop"),("Tile Library","square.grid.3x3"),("Result","photo"),("3D","cube")]
    var body:some View {
        NavigationStack {
            VStack(spacing:0) {
                if isPad {
                    GeometryReader { geometry in
                        HStack(spacing:0) {
                            if sidebarVisible {
                                SettingsSidebar(model: model, state: SidebarState(model: model),
                                                showsOutputDimensions: model.selectedTab == 0).equatable()
                                    .frame(width:sidebarWidth(in:geometry.size.width))
                                    .accessibilityIdentifier("settingsSidebar")
                                sidebarHandle(availableWidth:geometry.size.width)
                            }
                            VStack(spacing:0) {
                                Picker(L("Workspace"),selection:$model.selectedTab) {
                                    ForEach(0..<4) { index in Text(L(tabs[index].0)).tag(index) }
                                }.pickerStyle(.segmented).padding(12)
                                if !sidebarVisible && model.selectedTab == 0 {
                                    SettingsControls(model: model, state: SidebarState(model: model)).outputDimensions()
                                        .padding(.horizontal, 16).padding(.bottom, 8)
                                        .disabled(model.blocksEditing)
                                }
                                workspace(model.selectedTab)
                            }.frame(maxWidth:.infinity,maxHeight:.infinity)
                        }.coordinateSpace(name:"iPadWorkspace")
                    }
                    iPadStatusBar
                } else {
                    phoneWorkspace
                }
            }
            .navigationTitle("BraidArt").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement:.topBarLeading) {
                    if isPad {
                        Button { sidebarVisible.toggle() } label: {
                            Label(L(sidebarVisible ? "Hide sidebar" : "Show sidebar"),systemImage:"sidebar.left")
                        }.accessibilityIdentifier("sidebarToggle")
                        Button(action:model.chooseImage) { Label(L("Open…"),systemImage:"plus") }.disabled(model.busy)
                    }
                    Button { showingInfo=true } label: { Label(L("BraidArt Help"),systemImage:"info.circle") }.accessibilityIdentifier("help")
                }
                ToolbarItem(placement:.topBarTrailing) {
                    if model.blocksEditing {
                        Button(L("Cancel"),role:.cancel,action:model.cancel)
                    } else {
                        Button(L("Weave Image"),action:model.solve)
                            .font(isPad ? .body : .subheadline)
                            .fixedSize(horizontal:true,vertical:false)
                            .disabled(!model.canWeavePicture).tint(.orange).accessibilityIdentifier("weave")
                    }
                }
                if isPad && (model.selectedTab==2 || model.selectedTab==3) {
                    if #available(iOS 26.0,*) {
                        ToolbarSpacer(.fixed,placement:.topBarTrailing)
                    }
                    ToolbarItem(placement:.topBarTrailing) { exportMenu }
                }
            }
        }
        .tint(.orange)
        .dropDestination(for:URL.self) { urls,_ in
            guard !model.busy,let url=urls.first else { return false }
            model.importMobileFile(url);return true
        }
        .onChange(of:model.sceneSettings) { _,_ in model.sceneSettingsChanged() }
        .onChange(of:model.settings) { _,_ in model.settingsChanged() }
        .onChange(of: model.selectedTab) { _, _ in
            if liveSettings != nil { showLiveSettings(nil) }
        }
        .onChange(of: model.blocksEditing) { _, blocksEditing in
            if blocksEditing && liveSettings != nil { showLiveSettings(nil) }
        }
        .fullScreenCover(isPresented: $showingPhoneSettings) {
            PhoneSettingsScreen(model: model)
        }
        .confirmationDialog(L("Open Image, Video or Project…"),isPresented:$model.showingImportChoice,titleVisibility:.visible) {
            Button(L("Photos")) { model.showingPhotoImport=true }
            Button(L("Files")) { model.showingFileImport=true }
        }
        .fileImporter(isPresented:$model.showingFileImport,allowedContentTypes:[.image,.movie,.video,.json,.braidArtProject]) { result in
            switch result { case .success(let url): model.importMobileFile(url);case .failure(let error): model.error=error.localizedDescription }
        }
        .sheet(isPresented:$model.showingPhotoImport) {
            PhotoImporter { result in
                model.showingPhotoImport=false
                if let result {
                    switch result { case .success(let url): model.open(url:url);case .failure(let error): model.error=error.localizedDescription }
                }
            }.ignoresSafeArea()
        }
        .confirmationDialog(L("Save to"),isPresented:Binding(get:{model.mobileExport != nil},set:{if !$0,model.mobileExport != nil { model.mobileExport=nil }}),titleVisibility:.visible) {
            if let request=model.mobileExport {
                Button(L("Photos")) { request.start(.photos) }
                Button(L("Files")) { request.start(.files) }
            }
        }
        .sheet(item:$model.exportedFile) { file in
            FileExporter(url:file.url,complete:model.finishFileExport).interactiveDismissDisabled()
        }
        .sheet(isPresented:$showingInfo) { MobileInfoView() }
        .sheet(item:$model.dimensionManagerTarget) { DimensionManagerView(model:model,target:$0) }
        .sheet(item:$model.exportProgress) { ExportProgressView(export:$0,cancel:model.cancel).presentationDetents([.height(240)]) }
        .alert("BraidArt",isPresented:Binding(get:{model.error != nil},set:{if !$0 { model.error=nil }})) {
            Button(L("OK")) { model.error=nil }
        } message: { Text(model.error ?? "") }
        .task {
            FirstLaunchHelp.showIfNeeded { showingInfo=true }
        }
    }
    private var phoneWorkspace: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height
            let restingHeight = clampedPanelHeight(availableHeight * panelFraction, in: availableHeight)
            let panelHeight = clampedPanelHeight(restingHeight - panelDrag, in: availableHeight)
            VStack(spacing: 0) {
                if liveSettings == nil || showsCompact3DControls {
                    HStack(spacing: 12) {
                        if liveSettings == nil {
                            phoneSettingsBar
                                .frame(maxWidth: showsCompact3DControls ? 245 : .infinity)
                                .transition(.opacity)
                        }
                        if showsCompact3DControls {
                            sculptureControls.fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                TabView(selection: $model.selectedTab) {
                    ForEach(tabs.indices, id: \.self) { index in
                        workspace(index, bottomInset: liveSettings == nil ? 0 : panelHeight + 8)
                            .toolbar(liveSettings == nil ? .visible : .hidden, for: .tabBar)
                            .tabItem { Label(L(index == 1 ? "Tile Library tab" : tabs[index].0), systemImage: tabs[index].1) }
                            .tag(index)
                    }
                }
                .overlay(alignment: .top) {
                    if model.blocksEditing && model.exportProgress == nil {
                        phoneProgressOverlay
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let liveSettings {
                    phoneSettingsPanel(liveSettings, height: panelHeight, restingHeight: restingHeight,
                                       availableHeight: availableHeight)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: "phoneWorkspace")
        }
    }

    private var phoneSettingsBar: some View {
        HStack(spacing: 0) {
            Button(action: model.chooseImage) {
                settingsIcon(L("Open Image, Video or Project…"), symbol: "plus")
            }
            .disabled(model.busy)
            .accessibilityIdentifier("openSettingsMedia")
            ForEach(PhoneLiveSettings.allCases.filter { $0.isAvailable(on: model.selectedTab) }) { panel in
                Button { showLiveSettings(panel) } label: {
                    settingsIcon(panel.title, symbol: panel.symbol)
                }
                .disabled(model.blocksEditing)
                .accessibilityIdentifier(panel.rawValue)
            }
            Button { showingPhoneSettings = true } label: {
                settingsIcon(L("Settings"), symbol: "gearshape")
            }
            .disabled(model.blocksEditing)
            .accessibilityIdentifier("phoneSettings")
            exportMenu
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .frame(maxWidth: 560)
        .background { phoneSettingsBackground }
        .frame(maxWidth: .infinity)
    }

    private func settingsIcon(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.body.weight(.medium))
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(title)
    }

    private var phoneSettingsBackground: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(.regularMaterial)
            .matchedGeometryEffect(id: "settingsBackground", in: settingsAnimation)
    }

    private func phoneSettingsPanel(_ panel: PhoneLiveSettings, height: CGFloat, restingHeight: CGFloat,
                                    availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                VStack(spacing: 6) {
                    Capsule()
                        .fill(.secondary.opacity(0.45))
                        .frame(width: 36, height: 4)
                        .accessibilityHidden(true)
                    Text(panel.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                .padding(.horizontal, 48)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("phoneWorkspace"))
                    .updating($panelDrag) { value, offset, _ in offset = value.translation.height }
                    .onEnded { value in
                        resizeSettingsPanel(to: restingHeight - value.translation.height, in: availableHeight)
                    })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(panel.title)
                .accessibilityValue(L("%@ points", String(Int(height))))
                .accessibilityHint(L("Resize settings panel"))
                .accessibilityAdjustableAction { direction in
                    resizeSettingsPanel(to: height + (direction == .increment ? 44 : -44), in: availableHeight)
                }
                .accessibilityIdentifier("resizeSettingsPanel")
                Button { showLiveSettings(nil) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Close"))
                .accessibilityIdentifier("closeLiveSettings")
            }
            Divider()
            ScrollView {
                panel.controls(SettingsControls(model: model, state: SidebarState(model: model)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .disabled(model.blocksEditing)
            }
            .accessibilityIdentifier("liveSettingsScroll")
        }
        .frame(maxWidth: 560)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .background { phoneSettingsBackground.shadow(color: .black.opacity(0.16), radius: 14, y: 4) }
        .accessibilityAction(.escape) { showLiveSettings(nil) }
    }

    private func clampedPanelHeight(_ height: CGFloat, in available: CGFloat) -> CGFloat {
        let maximum = max(0, min(available * 0.78, available - 90))
        return min(max(height, 128), maximum)
    }

    private func resizeSettingsPanel(to height: CGFloat, in available: CGFloat) {
        guard available > 0 else { return }
        panelFraction = clampedPanelHeight(height, in: available) / available
    }

    private func showLiveSettings(_ panel: PhoneLiveSettings?) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.42)) {
            panelFraction = Self.initialPanelFraction
            liveSettings = panel
        }
    }

    private func sidebarWidth(in available:CGFloat)->Double {
        min(max(280,sidebarWidth),max(280,min(520,available-380)))
    }
    private func sidebarHandle(availableWidth:CGFloat)->some View {
        ZStack {
            Divider()
            Capsule().fill(.secondary.opacity(0.6)).frame(width:4,height:44)
        }
        .frame(width:18).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance:1,coordinateSpace:.named("iPadWorkspace")).onChanged { value in
            if sidebarResizeStart == nil { sidebarResizeStart=sidebarWidth(in:availableWidth) }
            sidebarWidth=min(max(280,(sidebarResizeStart ?? sidebarWidth)+value.translation.width),max(280,min(520,availableWidth-380)))
        }.onEnded { _ in sidebarResizeStart=nil })
        .accessibilityElement().accessibilityLabel(L("Resize sidebar"))
        .accessibilityValue(L("%@ points",String(Int(sidebarWidth(in:availableWidth)))))
        .accessibilityAdjustableAction { direction in
            sidebarWidth=sidebarWidth(in:availableWidth)+(direction == .increment ? 32 : -32)
            sidebarWidth=sidebarWidth(in:availableWidth)
        }
        .accessibilityIdentifier("sidebarResize")
    }
    @ViewBuilder private func workspace(_ index: Int, bottomInset: CGFloat = 0) -> some View {
        switch index {
        case 0: prepare(bottomInset: bottomInset)
        case 1: library(bottomInset: bottomInset)
        case 2: result
        case 3: sculpture
        default: EmptyView()
        }
    }
    private var exportMenu:some View {
        Menu {
            Button(L("Save Project…"),action:model.saveProject).disabled(model.project == nil)
            Button(L("Result as PNG…"),action:model.exportPNG).disabled(model.project == nil)
            Button(L("Weave Video…"),action:model.weaveVideo).disabled(!model.canWeaveVideo)
            Button(L("3D View as PNG…"),action:model.export3DPicture).disabled(model.selectedTab != 3 || model.curves == nil)
            Button(L("Vector PDF…"),action:model.exportPDF).disabled(model.curves == nil)
            Button(L("3D Object (GLB)…"),action:model.exportGLB).disabled(model.curves == nil)
            Button(L("3D Object (USDZ)…"),action:model.exportUSDZ).disabled(model.curves == nil)
            Button(L("Solution and Tile Data…"),action:model.exportData).disabled(model.project == nil)
        } label: {
            if isPad { Label(L("Save & export"),systemImage:"square.and.arrow.up") }
            else { settingsIcon(L("Save & export"), symbol: "square.and.arrow.up") }
        }
            .disabled(model.busy).accessibilityIdentifier("export")
    }
    private var phoneProgressOverlay: some View {
        Group {
            if model.isWeaving {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 240)
                    .accessibilityLabel(L("Weaving image"))
                    #if DEBUG
                    .accessibilityValue(model.backgroundWeavingTestValue ?? model.progress.formatted(.percent))
                    #endif
            } else {
                ProgressView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 8)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("phoneRenderingProgress")
        .allowsHitTesting(false)
    }

    private var iPadStatusBar:some View {
        VStack(alignment:.leading,spacing:4) {
            if model.blocksEditing { ProgressView(value:model.progress) }
            Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("status")
                #if DEBUG
                .accessibilityValue(model.backgroundWeavingTestValue ?? "")
                #endif
        }.padding(.horizontal,14).padding(.vertical,8).background(.bar)
    }
    @ViewBuilder private func prepare(bottomInset: CGFloat) -> some View {
        if model.sourceImage == nil && model.prepared == nil {
            VStack(alignment:.leading,spacing:0) {
                Text(L("A picture, reimagined as strands.")).font(.title2.bold()).padding(20)
                VStack(spacing:16) {
                    empty("photo.badge.plus",L("Start with an image or video"),L("Choose a picture or video from Photos or Files."))
                    Button(L("Open Image or Video…"),action:model.chooseImage)
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("openMedia")
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        } else {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text(L("A picture, reimagined as strands.")).font(.title2.bold())
                if let image=model.sourceImage {
                    CropEditor(image:image,crop:$model.settings.crop,hasSelection:$model.hasCropSelection,aspectRatio:model.cropAspectRatio,onDelete:model.resetCrop,player:model.videoPlayback?.player)
                        .frame(height:isPad ? 300 : 240).disabled(model.blocksEditing)
                    HStack {
                        Text(L("Pinch to scale. Drag to move or resize the crop.")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Reset Crop"),action:model.resetCrop).font(.caption)
                    }
                    if let video=model.videoSource,let segment=model.videoSegment,let playback=model.videoPlayback {
                        VideoTimelineView(playback:playback,source:video,segment:segment,selectFrame:model.selectVideoFrame,changeSegment:model.setVideoSegment,disabled:model.blocksEditing)
                    }
                }
                if let image=model.preparedImage {
                    Text(L("SAMPLED IMAGE")).font(.caption.bold()).foregroundStyle(.secondary)
                    Image(platformImage:image).resizable().interpolation(.none).scaledToFit().frame(maxWidth:.infinity,maxHeight:240)
                }
            }.padding(20)
        }
        .contentMargins(.bottom, bottomInset, for: .scrollContent)
        .accessibilityIdentifier("prepareWorkspace")
        }
    }
    private func library(bottomInset: CGFloat) -> some View {
        ScrollView {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:95),spacing:12)],spacing:16) {
                ForEach(model.tilePreviews) { preview in
                    VStack {
                        Image(platformImage:preview.image).resizable().scaledToFit()
                        Text("\(preview.tile.id) · \(preview.tile.kind.title)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(20)
        }
        .contentMargins(.bottom, bottomInset, for: .scrollContent)
        .accessibilityIdentifier("tileLibraryWorkspace")
    }
    private var result:some View {
        VStack(spacing:0) {
            if let image=model.resultImage {
                HStack {
                    Text(L("The woven image")).font(.headline)
                    Spacer()
                    Button(L("Fit")) { model.zoom=1 }
                }.padding(12)
                if model.resultNeedsWeaving { staleResult }
                ZoomableResult(image:image,zoom:$model.zoom).accessibilityIdentifier("resultCanvas")
                if model.videoSource != nil {
                    HStack {
                        Button(L("Weave Video…"),action:model.weaveVideo).disabled(!model.canWeaveVideo)
                        Toggle(L("Include audio"),isOn:$model.videoIncludeAudio)
                    }.padding(12)
                    Picker(L("Video format"),selection:$model.videoFormat) { ForEach(VideoOutputFormat.allCases) { Text($0.title).tag($0) } }.padding(.horizontal)
                }
            } else {
                empty("square.grid.3x3",L("Ready to weave"),L("Prepare a picture and choose your palette, then select Weave Image."))
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    private var sculpture:some View {
        VStack(spacing:0) {
            if let braid=model.curves {
                if !isCompactPhone { sculptureControls }
                if model.sculptureNeedsWeaving { staleResult }
                Braid3DView(braid:braid,meshes:model.meshes,generation:model.curveGeneration,settings:model.sceneSettings,reset:model.cameraReset,camera:model.cameraState,onCameraChanged:model.cameraChanged,onViewReady:model.register3DView)
                    .accessibilityIdentifier("sculptureCanvas")
                    .overlay {
                        GeometryReader { proxy in
                            let frame=model.pictureExportSize.frame(in:CGRect(origin:.zero,size:proxy.size))
                            Rectangle().strokeBorder(.red,lineWidth:2).frame(width:frame.width,height:frame.height).position(x:frame.midX,y:frame.midY)
                        }.allowsHitTesting(false)
                    }
                if !isCompactPhone {
                    Text(L("One finger to rotate · Two fingers to pan · Pinch to zoom")).font(.caption).foregroundStyle(.secondary).padding(8)
                }
            } else { empty("cube",L("Curves become a sculpture"),L("Weave an image or open a saved project to inspect its connected strands in 3D.")) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).disabled(model.busy)
    }
    private var sculptureControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                Button(action: model.resetCamera) {
                    Label(L("Reset Camera"), systemImage: "arrow.counterclockwise")
                }.accessibilityIdentifier("resetCamera")
                ColorPicker(L("Backing plane"), selection: Binding(get: { model.sceneSettings.planeColor.color },
                            set: { model.sceneSettings.planeColor = RGB(color: $0) }), supportsOpacity: false).fixedSize()
                Text(L("Clearance")).font(.caption)
                Slider(value: $model.sceneSettings.planeDistance, in: 0...3).frame(width: 110)
                if isPad {
                    DimensionPicker.for3DPicture(model: model)
                        .accessibilityIdentifier("pictureDimensionsPicker")
                }
            }
            .font(isCompactPhone ? .caption : .body)
            .padding(isCompactPhone ? 0 : 12)
        }
        .disabled(model.busy)
    }
    private var staleResult:some View { Text(L("Showing the previous result. Weave again to apply the current settings.")).font(.caption).foregroundStyle(.orange).padding(8) }
    private func empty(_ symbol:String,_ title:String,_ detail:String)->some View {
        VStack(spacing:16) {
            Image(systemName:symbol).font(.system(size:50)).foregroundStyle(.orange)
            Text(title).font(.title2)
            Text(detail).foregroundStyle(.secondary)
        }.multilineTextAlignment(.center).padding(24).frame(maxWidth:.infinity)
    }
}
