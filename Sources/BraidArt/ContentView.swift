import SwiftUI
import UniformTypeIdentifiers
import BraidCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isDropTargeted=false
    var body: some View {
        HSplitView {
            SettingsSidebar(model:model,state:SidebarState(model:model)).equatable()
            VStack(spacing:0) {
                HStack {
                    Picker(L("Workspace"),selection:$model.selectedTab) {
                        Text(L("Prepare")).tag(0);Text(L("Tile Library")).tag(1);Text(L("Result")).tag(2);Text(L("3D")).tag(3)
                    }.pickerStyle(.segmented).frame(width:380)
                    Spacer()
                    if model.blocksEditing {
                        Button(L("Cancel"),role:.cancel,action:model.cancel)
                    } else {
                        Button(action:model.solve) { Label(L("Weave Image"),systemImage:"play.fill") }.buttonStyle(.borderedProminent).tint(.orange)
                            .disabled(model.busy || model.prepared==nil || model.solverURL==nil || !model.preparedIsCurrent || (try? model.settings.validate()) == nil)
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
                    if model.blocksEditing { ProgressView(value:model.progress).tint(.orange) }
                    HStack(spacing:10) {
                        Circle().fill(model.busy ? Color.orange : Color.secondary.opacity(0.6)).frame(width:6,height:6)
                        Text(model.status).font(.caption).lineLimit(2)
                        Spacer(minLength:12)
                        Label(L("Metal"),systemImage:"bolt.fill").font(.caption2).foregroundStyle(.secondary).help(model.gpuName)
                    }
                }.padding(14).background(.bar)
            }.frame(minWidth:700)
        }
        .contentShape(Rectangle())
        .dropDestination(for:URL.self) { urls,_ in
            guard !model.busy,let url=urls.first(where: { url in
                guard url.isFileURL else { return false }
                let ext=url.pathExtension.lowercased()
                return UTType(filenameExtension:ext)?.conforms(to:.image) == true || ext == "braidart" || ext == "json"
            }) else { return false }
            model.open(url:url)
            return true
        } isTargeted: { isDropTargeted=$0 }
        .overlay {
            if isDropTargeted && !model.busy {
                RoundedRectangle(cornerRadius:12).strokeBorder(.orange,lineWidth:3).padding(6)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .onChange(of:model.sceneSettings) { _,_ in model.sceneSettingsChanged() }
        .onChange(of:model.settings) { _,_ in model.settingsChanged() }
        .sheet(item:$model.dimensionManagerTarget) { target in
            DimensionManagerView(model:model,target:target)
        }
        .sheet(item:$model.exportProgress) { export in ExportProgressView(export:export,cancel:model.cancel) }
        .alert("BraidArt",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error=nil}})) { Button(L("OK")) { model.error=nil } } message:{Text(model.error ?? "")}
    }
    private var prepareWorkspace: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                title(L("A picture, reimagined as strands."),subtitle:L("Crop the source, choose a tile resolution, then weave."))
                if let image=model.sourceImage {
                    Text(L("SOURCE & CROP")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing:12) {
                        DimensionPicker(title:L("Output dimensions"),selection:Binding(get:{model.settings.outputSize},set:{model.setOutputSize($0)}),customDimensions:model.customDimensions,onManage:{model.dimensionManagerTarget = .output})
                            .frame(maxWidth:430)
                        Spacer(minLength:0)
                        Button { model.scaleCrop(by:1/1.1) } label: { Image(systemName:"minus.magnifyingglass") }
                            .help(L("Scale crop down")).accessibilityLabel(L("Scale crop down")).disabled(!model.hasCropSelection)
                        Button { model.scaleCrop(by:1.1) } label: { Image(systemName:"plus.magnifyingglass") }
                            .help(L("Scale crop up")).accessibilityLabel(L("Scale crop up")).disabled(!model.hasCropSelection)
                        Button(L("Reset Crop"),action:model.resetCrop).disabled(!model.hasCropSelection)
                    }.controlSize(.small).disabled(model.blocksEditing)
                    CropEditor(image:image,crop:$model.settings.crop,hasSelection:$model.hasCropSelection,aspectRatio:model.cropAspectRatio,onDelete:model.resetCrop)
                        .frame(height:350).disabled(model.blocksEditing)
                    Text(L("Drag inside to move; drag an edge or corner to resize. Pinch or use − / + to scale. Drag outside the crop to draw another rectangle. Reset Crop restores the largest crop."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(model.hasCropSelection ? L("Crop: %@%% × %@%% of source", String(describing: Int(model.settings.crop.width*100)), String(describing: Int(model.settings.crop.height*100))) : L("Using the full picture."))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else if model.prepared == nil {
                    emptyState(symbol:"photo.badge.plus",title:L("Start with a picture"),detail:L("Drop a photograph or illustration here, or choose one. Each sample will become a connected braid tile."),button:L("Open Image…"),action:model.chooseImage).frame(height:360)
                }
                if let image=model.preparedImage {
                    HStack { Text(L("SAMPLED IMAGE")).font(.caption.weight(.semibold)).foregroundStyle(.secondary);Spacer();if let p=model.prepared {Text(L("%@ × %@", String(describing: p.width), String(describing: p.height))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)} }
                    Image(nsImage:image).resizable().interpolation(.none).scaledToFit().frame(maxWidth:.infinity,maxHeight:300).padding(16).background(Color.black.opacity(0.15),in:RoundedRectangle(cornerRadius:12))
                    Text(L("One sample becomes one tile. The optimizer matches each tile’s average color to this image.")).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28)
        }
    }
    private var tileLibrary: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                title(L("The building blocks."),subtitle:L("All color pairs, four geometries. IDs match the notebook’s tile order."))
                LazyVGrid(columns:[GridItem(.adaptive(minimum:100),spacing:14)],spacing:20) {
                    ForEach(model.tilePreviews) { preview in
                        VStack(alignment:.leading,spacing:6) {
                            Image(nsImage:preview.image).resizable().interpolation(.high).aspectRatio(1,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:5))
                            Text(L("%@ · %@", String(describing: preview.tile.id), String(describing: preview.tile.kind.title))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
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
                        Text(L("The woven image")).font(.title2.weight(.semibold))
                        Text(L("%@ × %@ tiles · %@ parts · mean ΔE %@", String(describing: project.sampledImage.width), String(describing: project.sampledImage.height), String(describing: project.result.reports.count), String(describing: String(format:"%.2f",project.result.objective/Double(project.sampledImage.pixels.count))))).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(L("Zoom")).font(.caption)
                    Slider(value:$model.zoom,in:0.25...4).frame(width:100)
                    Button(L("Fit")) { model.zoom=1 }.controlSize(.small)
                }.padding(22)
                if model.resultNeedsWeaving {
                    Label(L("Showing the previous result. Weave again to apply the current settings."),systemImage:"clock.arrow.circlepath").font(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,22).padding(.bottom,12)
                }
                GeometryReader { proxy in
                    let fit=min((proxy.size.width-40)/image.size.width,(proxy.size.height-40)/image.size.height)
                    ScrollView([.horizontal,.vertical]) {
                        Image(nsImage:image).resizable().interpolation(.high).frame(width:max(1,image.size.width*fit*model.zoom),height:max(1,image.size.height*fit*model.zoom)).padding(20)
                            .frame(minWidth:proxy.size.width,minHeight:proxy.size.height)
                    }
                }.background(Color.black.opacity(0.15))
                HStack {
                    Label(project.result.allPartitionsOptimal ? L("Parts proven optimal") : L("Feasible · time or gap limited"),systemImage:project.result.allPartitionsOptimal ? "checkmark.seal" : "clock").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(project.result.costBackend).font(.caption2).foregroundStyle(.secondary)
                }.padding(16)
            } else {
                emptyState(symbol:"square.grid.3x3",title:model.busy ? L("Weaving your image") : L("Ready to weave"),detail:model.busy ? L("Each part is solved with strand continuity constraints. Progress appears below.") : L("Prepare a picture and choose your palette, then select Weave Image."),button:nil,action:{}).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
    }
    private var threeDWorkspace: some View {
        VStack(spacing:0) {
            if let braid=model.curves {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        Text(L("The woven sculpture")).font(.title2.weight(.semibold))
                        Text(L("%@ curves · Metal · drag to rotate, Shift-drag or right-drag to pan, scroll or pinch to zoom", String(describing: braid.curves.count))).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Front / Fit")) { model.resetCamera(oblique:false) }
                    Button(L("Perspective")) { model.resetCamera(oblique:true) }
                }.padding(20)
                HStack(spacing:20) {
                    ColorPicker(L("Backing plane"),selection:Binding(get:{model.sceneSettings.planeColor.color},set:{model.sceneSettings.planeColor=RGB(color:$0)}),supportsOpacity:false).frame(maxWidth:230)
                    Text(L("Clearance")).font(.caption)
                    Slider(value:$model.sceneSettings.planeDistance,in:0...3).frame(maxWidth:180)
                    Text(String(format:L("%.2f tiles"),model.sceneSettings.planeDistance)).font(.caption.monospacedDigit()).frame(width:75)
                    Spacer()
                }.padding(.horizontal,20).padding(.bottom,16)
                HStack(spacing:16) {
                    DimensionPicker(title:L("Picture dimensions"),selection:$model.pictureExportSize,customDimensions:model.customDimensions,includeViewport:true,onManage:{model.dimensionManagerTarget = .picture})
                        .fixedSize()
                    Text(L("The red frame marks the exported area.")).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength:0)
                }.padding(.horizontal,20).padding(.bottom,16)
                if model.resultNeedsWeaving {
                    Label(L("Showing the previous result. Weave again to apply the current settings."),systemImage:"clock.arrow.circlepath").font(.caption).foregroundStyle(.orange).padding(.bottom,12)
                }
                Braid3DView(braid:braid,meshes:model.meshes,generation:model.curveGeneration,settings:model.sceneSettings,reset:model.cameraReset,oblique:model.obliqueCamera,camera:model.cameraState,onCameraChanged:model.cameraChanged,onViewReady:model.register3DView)
                    .overlay {
                        GeometryReader { proxy in
                            let frame=model.pictureExportSize.frame(in:CGRect(origin:.zero,size:proxy.size))
                            Rectangle().strokeBorder(.red,lineWidth:2)
                                .frame(width:frame.width,height:frame.height)
                                .position(x:frame.midX,y:frame.midY)
                        }.allowsHitTesting(false).accessibilityHidden(true)
                    }
                Text(L("Plane clearance is measured from the back of the lowest strand. Plane settings are saved with the project and 3D exports.")).font(.caption).foregroundStyle(.secondary).padding(14)
            } else {
                emptyState(symbol:"cube.transparent",title:L("Curves become a sculpture"),detail:L("Weave an image or open a saved project to inspect its connected strands in 3D."),button:nil,action:{}).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
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
