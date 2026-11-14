import SwiftUI
import BraidCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    HStack(spacing:10) {
                        Image(systemName:"circle.hexagongrid.fill").font(.system(size:29)).foregroundStyle(.orange)
                        VStack(alignment:.leading,spacing:2) { Text("BraidArt").font(.title2.bold());Text("IMAGE TO WOVEN TILES").font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(1.5).foregroundStyle(.secondary) }
                    }.padding(.bottom,6)
                    section("01", "Picture") {
                        Button(action:model.chooseImage) { Label("Open Image or Project…",systemImage:"photo.on.rectangle") }.controlSize(.large).frame(maxWidth:.infinity)
                        if !model.sourceName.isEmpty { Text(model.sourceName).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        Stepper("Image width: \(model.settings.columns) tiles",value:$model.settings.columns,in:8...256,step:2).disabled(model.sourceImage==nil)
                        if let image=model.prepared { Text("\(image.width) × \(image.height) = \(image.width*image.height) tiles").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        Toggle("Luminance only",isOn:$model.settings.grayscale).disabled(model.sourceImage==nil)
                        slider("Contrast",value:$model.settings.contrast,in:0.25...3).disabled(model.sourceImage==nil)
                        slider("Brightness",value:$model.settings.brightness,in:-0.5...0.5).disabled(model.sourceImage==nil)
                        if model.sourceImage != nil {
                            ColorPicker("Transparent areas",selection:colorBinding(\.alphaBackground),supportsOpacity:false)
                            Button("Reset Crop") { model.settings.crop=Crop() }.font(.caption)
                        } else if model.project != nil {
                            Text("This project contains the sampled image. Open the original picture to change the crop or resize.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    section("02", "Tiles & palette") {
                        ColorPicker("Background",selection:colorBinding(\.background),supportsOpacity:false)
                        ForEach(model.settings.palette.indices,id:\.self) { index in
                            HStack {
                                ColorPicker("Strand \(index+1)",selection:Binding(get:{model.settings.palette[index].color},set:{model.settings.palette[index]=RGB(color:$0)}),supportsOpacity:false)
                                if model.settings.palette.count>1 { Button { model.settings.palette.remove(at:index) } label:{Image(systemName:"minus.circle")}.buttonStyle(.plain).foregroundStyle(.secondary).help("Remove strand color") }
                            }
                        }
                        HStack {
                            Button("Black & White") { model.settings.palette=[.black,.white] }
                            Spacer()
                            Button { if model.settings.palette.count<8 { model.settings.palette.append(RGB(Double.random(in:0...1),Double.random(in:0...1),Double.random(in:0...1))) } } label:{Image(systemName:"plus")}.disabled(model.settings.palette.count>=8).help("Add strand color")
                        }
                        HStack {
                            Stepper("\(model.paletteCount) colors",value:$model.paletteCount,in:2...8)
                            Button("Extract",action:model.extractPalette).disabled(model.prepared==nil).help("Find dominant colors in the prepared picture")
                        }
                        Text("\(model.settings.palette.count*model.settings.palette.count*4) dark tiles · four strand geometries").font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Strand geometry") {
                            VStack(spacing:8) {
                                slider("Width",value:$model.settings.strandWidth,in:0.1...min(0.6,0.98-model.settings.gap))
                                slider("Crossing gap",value:$model.settings.gap,in:0...min(0.6,0.98-model.settings.strandWidth))
                                Text("Defaults match the notebook: width 0.414, gap 0.4.").font(.caption2).foregroundStyle(.secondary)
                            }.padding(.top,8)
                        }
                    }
                    section("03", "Partition solve") {
                        Stepper("Part size: \(model.settings.partitionSize) × \(model.settings.partitionSize)",value:$model.settings.partitionSize,in:1...20)
                        Picker("Time per part",selection:$model.settings.secondsPerPartition) {
                            Text("5 seconds").tag(5.0);Text("30 seconds").tag(30.0);Text("2 minutes").tag(120.0);Text("10 minutes").tag(600.0)
                        }
                        Picker("Optimality gap",selection:$model.settings.relativeGap) {
                            Text("Exact (0%)").tag(0.0);Text("1%").tag(0.01);Text("5%").tag(0.05)
                        }
                        Stepper("CPU threads: \(model.settings.threads)",value:$model.settings.threads,in:1...16)
                        Text("Parts preserve strand colors along their top and left neighbors. Smaller parts solve faster.").font(.caption).foregroundStyle(.secondary)
                        if model.solverURL == nil {
                            Label("CBC solver needed",systemImage:"exclamationmark.triangle").foregroundStyle(.orange)
                            Button("Choose CBC Executable…",action:model.selectSolver)
                            Text("Run Scripts/build-solver.sh when building from source. The packaged app includes the solver.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            HStack { Label("COIN-OR CBC + CLP",systemImage:"checkmark.circle.fill").foregroundStyle(.green);Spacer();Button(action:model.selectSolver){Image(systemName:"ellipsis")}.buttonStyle(.plain).help("Choose another CBC executable") }.font(.caption)
                        }
                    }
                    section("04", "Save & export") {
                        Picker("PNG tile size",selection:$model.exportTileSize) {
                            Text("20 px").tag(20);Text("50 px").tag(50);Text("100 px").tag(100)
                        }
                        Button("Save Project…",action:model.saveProject).disabled(model.project==nil)
                        Button("Export PNG…",action:model.exportPNG).disabled(model.project==nil)
                        Button("Export Vector PDF…",action:model.exportPDF).disabled(model.curves==nil)
                        Button("Export 3D Object (GLB)…",action:model.exportGLB).disabled(model.curves==nil)
                        Button("Export 3D Object (USDZ)…",action:model.exportUSDZ).disabled(model.curves==nil)
                        Button("Export Solution & Tile Data…",action:model.exportData).disabled(model.project==nil)
                        Text("Data export includes JSON, Wolfram data and tile images for subsequent processing.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(22).disabled(model.busy)
            }.frame(minWidth:290,idealWidth:320,maxWidth:370)
                .background(Color(nsColor:.controlBackgroundColor))
            VStack(spacing:0) {
                HStack {
                    Picker("Workspace",selection:$model.selectedTab) {
                        Text("Prepare").tag(0);Text("Tile Library").tag(1);Text("Result").tag(2);Text("3D").tag(3)
                    }.pickerStyle(.segmented).frame(width:380)
                    Spacer()
                    if model.busy {
                        Button("Cancel",role:.cancel,action:model.cancel)
                    } else {
                        Button(action:model.solve) { Label("Weave Image",systemImage:"play.fill") }.buttonStyle(.borderedProminent).tint(.orange)
                            .disabled(model.prepared==nil || model.solverURL==nil || !model.preparedIsCurrent || (try? model.settings.validate()) == nil)
                            .keyboardShortcut(.return,modifiers:.command)
                    }
                }.padding(18).background(.bar)
                Group {
                    switch model.selectedTab {
                    case 0: prepareWorkspace
                    case 1: tileLibrary
                    case 3: threeDWorkspace.disabled(model.busy)
                    default: resultWorkspace
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                Divider()
                VStack(alignment:.leading,spacing:8) {
                    if model.busy { ProgressView(value:model.progress).tint(.orange) }
                    HStack(spacing:10) {
                        Circle().fill(model.busy ? Color.orange : Color.secondary.opacity(0.6)).frame(width:6,height:6)
                        Text(model.status).font(.caption).lineLimit(2)
                        Spacer(minLength:12)
                        Label("Metal",systemImage:"bolt.fill").font(.caption2).foregroundStyle(.secondary).help(model.gpuName)
                    }
                }.padding(14).background(.bar)
            }.frame(minWidth:700)
        }
        .onChange(of:model.sceneSettings) { _,_ in model.sceneSettingsChanged() }
        .onChange(of:model.settings) { _,_ in model.settingsChanged() }
        .sheet(item:$model.exportProgress) { export in ExportProgressView(export:export,cancel:model.cancel) }
        .alert("BraidArt",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error=nil}})) { Button("OK") { model.error=nil } } message:{Text(model.error ?? "")}
    }
    private var prepareWorkspace: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                title("A picture, reimagined as strands.",subtitle:"Crop the source, choose a tile resolution, then weave.")
                if let image=model.sourceImage {
                    HStack { Text("SOURCE & CROP").font(.caption.weight(.semibold)).foregroundStyle(.secondary);Spacer();Text("Drag to select a crop").font(.caption).foregroundStyle(.secondary) }
                    CropEditor(image:image,crop:$model.settings.crop).frame(height:350).disabled(model.busy)
                    Text("Crop: \(Int(model.settings.crop.width*100))% × \(Int(model.settings.crop.height*100))% of source").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else if model.prepared == nil {
                    emptyState(symbol:"photo.badge.plus",title:"Start with a picture",detail:"Choose a photograph or illustration. Each sample will become a connected braid tile.",button:"Open Image…",action:model.chooseImage).frame(height:360)
                }
                if let image=model.preparedImage {
                    HStack { Text("SAMPLED IMAGE").font(.caption.weight(.semibold)).foregroundStyle(.secondary);Spacer();if let p=model.prepared {Text("\(p.width) × \(p.height)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)} }
                    Image(nsImage:image).resizable().interpolation(.none).scaledToFit().frame(maxWidth:.infinity,maxHeight:300).padding(16).background(Color.black.opacity(0.15),in:RoundedRectangle(cornerRadius:12))
                    Text("One sample becomes one tile. The optimizer matches each tile’s average color to this image.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28)
        }
    }
    private var tileLibrary: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                title("The building blocks.",subtitle:"All color pairs, four geometries. IDs match the notebook’s tile order.")
                LazyVGrid(columns:[GridItem(.adaptive(minimum:100),spacing:14)],spacing:20) {
                    ForEach(Array(model.tileImages.enumerated()),id:\.offset) { index,image in
                        VStack(alignment:.leading,spacing:6) {
                            Image(nsImage:image).resizable().interpolation(.high).aspectRatio(1,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:5))
                            Text("\(index+1) · \(model.tileData.allTiles[index].kind.rawValue)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(28)
        }
    }
    private var resultWorkspace: some View {
        VStack(spacing:0) {
            if let image=model.resultImage,let project=model.project {
                HStack(spacing:20) {
                    VStack(alignment:.leading,spacing:4) {
                        Text("The woven image").font(.title2.weight(.semibold))
                        Text("\(project.sampledImage.width) × \(project.sampledImage.height) tiles · \(project.result.reports.count) parts · mean ΔE \(String(format:"%.2f",project.result.objective/Double(project.sampledImage.pixels.count)))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Zoom").font(.caption)
                    Slider(value:$model.zoom,in:0.25...4).frame(width:100)
                    Button("Fit") { model.zoom=1 }.controlSize(.small)
                }.padding(22)
                if project.settings != model.settings {
                    Label("Showing the previous result. Weave again to apply the current settings.",systemImage:"clock.arrow.circlepath").font(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,22).padding(.bottom,12)
                }
                GeometryReader { proxy in
                    let fit=min((proxy.size.width-40)/image.size.width,(proxy.size.height-40)/image.size.height)
                    ScrollView([.horizontal,.vertical]) {
                        Image(nsImage:image).resizable().interpolation(.high).frame(width:max(1,image.size.width*fit*model.zoom),height:max(1,image.size.height*fit*model.zoom)).padding(20)
                            .frame(minWidth:proxy.size.width,minHeight:proxy.size.height)
                    }
                }.background(Color.black.opacity(0.15))
                HStack {
                    Label(project.result.allPartitionsOptimal ? "Parts proven optimal" : "Feasible · time or gap limited",systemImage:project.result.allPartitionsOptimal ? "checkmark.seal" : "clock").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(project.result.costBackend).font(.caption2).foregroundStyle(.secondary)
                }.padding(16)
            } else {
                emptyState(symbol:"square.grid.3x3",title:model.busy ? "Weaving your image" : "Ready to weave",detail:model.busy ? "Each part is solved with strand continuity constraints. Progress appears below." : "Prepare a picture and choose your palette, then select Weave Image.",button:nil,action:{}).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
    }
    private var threeDWorkspace: some View {
        VStack(spacing:0) {
            if let braid=model.curves {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        Text("The woven sculpture").font(.title2.weight(.semibold))
                        Text("\(braid.curves.count) curves · Metal · drag to rotate, Shift-drag or right-drag to pan, scroll or pinch to zoom").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Front / Fit") { model.resetCamera(oblique:false) }
                    Button("Perspective") { model.resetCamera(oblique:true) }
                    Button("Export Picture…",action:model.export3DPicture).disabled(model.busy)
                }.padding(20)
                HStack(spacing:20) {
                    ColorPicker("Backing plane",selection:Binding(get:{model.sceneSettings.planeColor.color},set:{model.sceneSettings.planeColor=RGB(color:$0)}),supportsOpacity:false).frame(maxWidth:230)
                    Text("Clearance").font(.caption)
                    Slider(value:$model.sceneSettings.planeDistance,in:0...3).frame(maxWidth:180)
                    Text(String(format:"%.2f tiles",model.sceneSettings.planeDistance)).font(.caption.monospacedDigit()).frame(width:75)
                    Spacer()
                }.padding(.horizontal,20).padding(.bottom,16)
                if let project=model.project,project.settings != model.settings {
                    Label("Showing the previous result. Weave again to apply the current settings.",systemImage:"clock.arrow.circlepath").font(.caption).foregroundStyle(.orange).padding(.bottom,12)
                }
                Braid3DView(braid:braid,meshes:model.meshes,generation:model.curveGeneration,settings:model.sceneSettings,reset:model.cameraReset,oblique:model.obliqueCamera,onViewReady:model.register3DView)
                Text("Plane clearance is measured from the back of the lowest strand. Plane settings are saved with the project and 3D exports.").font(.caption).foregroundStyle(.secondary).padding(14)
            } else {
                emptyState(symbol:"cube.transparent",title:"Curves become a sculpture",detail:"Weave an image or open a saved project to inspect its connected strands in 3D.",button:nil,action:{}).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
    }
    private func colorBinding(_ path: WritableKeyPath<BraidCore.Settings,RGB>)->Binding<Color> { Binding(get:{model.settings[keyPath:path].color},set:{model.settings[keyPath:path]=RGB(color:$0)}) }
    private func section<C:View>(_ number: String,_ text: String,@ViewBuilder content:()->C)->some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text(number).font(.caption.monospaced().weight(.semibold)).foregroundStyle(.orange);Text(text).font(.headline) }
            content()
        }
    }
    private func slider(_ label: String,value: Binding<Double>,in range: ClosedRange<Double>)->some View {
        VStack(alignment:.leading,spacing:4) { HStack{Text(label);Spacer();Text(String(format:"%.3f",value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)}.font(.caption);Slider(value:value,in:range) }
    }
    private func title(_ text: String,subtitle: String)->some View { VStack(alignment:.leading,spacing:8) {Text(text).font(.system(size:28,weight:.semibold,design:.rounded));Text(subtitle).foregroundStyle(.secondary)} }
    private func emptyState(symbol:String,title:String,detail:String,button:String?,action:@escaping()->Void)->some View {
        VStack(spacing:16) {
            Image(systemName:symbol).font(.system(size:56,weight:.ultraLight)).foregroundStyle(.orange)
            Text(title).font(.title2.weight(.medium))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth:340)
            if let button=button { Button(button,action:action).controlSize(.large).buttonStyle(.borderedProminent).tint(.orange).disabled(model.busy) }
        }.padding(30)
    }
}

struct CropEditor: View {
    let image: NSImage
    @Binding var crop: Crop
    @State private var anchor: CGPoint?
    @State private var draft: CGRect?
    var body: some View {
        GeometryReader { proxy in
            let size=image.size,scale=min(proxy.size.width/size.width,proxy.size.height/size.height)
            let fitted=CGSize(width:size.width*scale,height:size.height*scale)
            let offset=CGPoint(x:(proxy.size.width-fitted.width)/2,y:(proxy.size.height-fitted.height)/2)
            let normalized=CGRect(x:crop.x,y:crop.y,width:crop.width,height:crop.height)
            let rect=draft ?? normalized
            ZStack(alignment:.topLeading) {
                Color.black.opacity(0.2)
                Image(nsImage:image).resizable().frame(width:fitted.width,height:fitted.height).offset(x:offset.x,y:offset.y)
                Path { path in
                    path.addRect(CGRect(origin:offset,size:fitted))
                    path.addRect(CGRect(x:offset.x+rect.minX*fitted.width,y:offset.y+rect.minY*fitted.height,width:rect.width*fitted.width,height:rect.height*fitted.height))
                }.fill(.black.opacity(0.45),style:FillStyle(eoFill:true))
                Rectangle().stroke(.orange,lineWidth:2).frame(width:rect.width*fitted.width,height:rect.height*fitted.height).offset(x:offset.x+rect.minX*fitted.width,y:offset.y+rect.minY*fitted.height)
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:3).onChanged { value in
                    func point(_ p:CGPoint)->CGPoint {CGPoint(x:min(1,max(0,(p.x-offset.x)/fitted.width)),y:min(1,max(0,(p.y-offset.y)/fitted.height)))}
                    if anchor==nil {anchor=point(value.startLocation)}
                    let start=anchor!,end=point(value.location)
                    draft=CGRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(end.x-start.x),height:abs(end.y-start.y))
                }.onEnded { _ in
                    if let r=draft,r.width>0.02,r.height>0.02 {crop=Crop(x:r.minX,y:r.minY,width:r.width,height:r.height)}
                    anchor=nil;draft=nil
                })
        }.clipShape(RoundedRectangle(cornerRadius:12))
    }
}
