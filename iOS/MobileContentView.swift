import SwiftUI
import BraidCore
import UniformTypeIdentifiers

struct MobileContentView:View {
    @ObservedObject var model:AppModel
    @State private var showingInfo=false
    @AppStorage("iPadSidebarWidth") private var sidebarWidth=330.0
    @AppStorage("iPadSidebarVisible") private var sidebarVisible=true
    @State private var sidebarResizeStart:Double?
    private var isPad:Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private let tabs=[("Prepare","crop"),("Tile Library","square.grid.3x3"),("Result","photo"),("3D","cube"),("Settings","slider.horizontal.3")]
    var body:some View {
        NavigationStack {
            VStack(spacing:0) {
                if isPad {
                    GeometryReader { geometry in
                        HStack(spacing:0) {
                            if sidebarVisible {
                                SettingsSidebar(model:model,state:SidebarState(model:model)).equatable()
                                    .frame(width:sidebarWidth(in:geometry.size.width))
                                    .accessibilityIdentifier("settingsSidebar")
                                sidebarHandle(availableWidth:geometry.size.width)
                            }
                            VStack(spacing:0) {
                                Picker(L("Workspace"),selection:$model.selectedTab) {
                                    ForEach(0..<4) { index in Text(L(tabs[index].0)).tag(index) }
                                }.pickerStyle(.segmented).padding(12)
                                workspace(model.selectedTab)
                            }.frame(maxWidth:.infinity,maxHeight:.infinity)
                        }.coordinateSpace(name:"iPadWorkspace")
                    }
                } else {
                    TabView(selection:$model.selectedTab) {
                        ForEach(0..<5) { index in
                            workspace(index).tabItem { Label(L(tabs[index].0),systemImage:tabs[index].1) }.tag(index)
                        }
                    }
                }
                statusBar
            }
            .navigationTitle("BraidArt").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement:.topBarLeading) {
                    if isPad {
                        Button { sidebarVisible.toggle() } label: {
                            Label(L(sidebarVisible ? "Hide sidebar" : "Show sidebar"),systemImage:"sidebar.left")
                        }.accessibilityIdentifier("sidebarToggle")
                    }
                    Button(action:model.chooseImage) { Label(L("Open…"),systemImage:"plus") }.disabled(model.busy)
                    Button { showingInfo=true } label: { Label(L("BraidArt Help"),systemImage:"info.circle") }.accessibilityIdentifier("help")
                }
                ToolbarItem(placement:.topBarTrailing) {
                    if model.blocksEditing {
                        Button(L("Cancel"),role:.cancel,action:model.cancel)
                    } else {
                        Button(L("Weave Image"),action:model.solve)
                            .fixedSize(horizontal:true,vertical:false)
                            .disabled(!model.canWeavePicture).tint(.orange).accessibilityIdentifier("weave")
                    }
                }
                if model.selectedTab==2 || model.selectedTab==3 {
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
    @ViewBuilder private func workspace(_ index:Int)->some View {
        switch index {
        case 0: prepare
        case 1: library
        case 2: result
        case 3: sculpture
        default: SettingsSidebar(model:model,state:SidebarState(model:model)).equatable()
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
        } label: { Label(L("Save & export"),systemImage:"square.and.arrow.up") }
            .disabled(model.busy).accessibilityIdentifier("export")
    }
    private var statusBar:some View {
        VStack(alignment:.leading,spacing:4) {
            if model.blocksEditing { ProgressView(value:model.progress) }
            Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("status")
                #if DEBUG
                .accessibilityValue(model.backgroundWeavingTestValue)
                #endif
        }.padding(.horizontal,14).padding(.vertical,8).background(.bar)
    }
    @ViewBuilder private var prepare:some View {
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
                    DimensionPicker(title:L("Output dimensions"),selection:Binding(get:{model.settings.outputSize},set:model.setOutputSize),customDimensions:model.customDimensions,onManage:{model.dimensionManagerTarget = .output})
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
        }
    }
    private var library:some View {
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
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:16) {
                        Button(L("Front / Fit")) { model.resetCamera(oblique:false) }
                        Button(L("Perspective")) { model.resetCamera(oblique:true) }
                        ColorPicker(L("Backing plane"),selection:Binding(get:{model.sceneSettings.planeColor.color},set:{model.sceneSettings.planeColor=RGB(color:$0)}),supportsOpacity:false).fixedSize()
                        Text(L("Clearance")).font(.caption)
                        Slider(value:$model.sceneSettings.planeDistance,in:0...3).frame(width:110)
                        DimensionPicker(title:L("Picture dimensions"),selection:$model.pictureExportSize,customDimensions:model.customDimensions,includeViewport:true,onManage:{model.dimensionManagerTarget = .picture})
                    }.padding(12)
                }
                if model.resultNeedsWeaving { staleResult }
                Braid3DView(braid:braid,meshes:model.meshes,generation:model.curveGeneration,settings:model.sceneSettings,reset:model.cameraReset,oblique:model.obliqueCamera,camera:model.cameraState,onCameraChanged:model.cameraChanged,onViewReady:model.register3DView)
                    .accessibilityIdentifier("sculptureCanvas")
                    .overlay {
                        GeometryReader { proxy in
                            let frame=model.pictureExportSize.frame(in:CGRect(origin:.zero,size:proxy.size))
                            Rectangle().strokeBorder(.red,lineWidth:2).frame(width:frame.width,height:frame.height).position(x:frame.midX,y:frame.midY)
                        }.allowsHitTesting(false)
                    }
                Text(L("One finger to rotate · Two fingers to pan · Pinch to zoom")).font(.caption).foregroundStyle(.secondary).padding(8)
            } else { empty("cube",L("Curves become a sculpture"),L("Weave an image or open a saved project to inspect its connected strands in 3D.")) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).disabled(model.busy)
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
