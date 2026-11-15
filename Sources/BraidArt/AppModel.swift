import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Metal
import BraidCore

extension RGB {
    var color: Color { Color(.sRGB,red:r,green:g,blue:b,opacity:1) }
    init(color: Color) {
        let c=NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(c.redComponent,c.greenComponent,c.blueComponent)
    }
}
extension CGImage { var nsImage: NSImage { NSImage(cgImage:self,size:NSSize(width:width,height:height)) } }

struct PaletteEntry: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let color: RGB
}

struct TilePreview: Identifiable {
    let tile: Tile
    let image: NSImage
    var id: Int { tile.id }
}

enum PaletteSeparation: String, CaseIterable, Identifiable {
    case keepShades="Keep shades", low="Low", medium="Medium", high="High"
    var id: Self { self }
    // Practical presets, rather than universal boundaries between color names.
    var minimumDistance: Double {
        switch self {
        case .keepShades: return 0
        case .low: return 6
        case .medium: return 12
        case .high: return 20
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings=BraidCore.Settings() {
        didSet {
            // A resized palette must not reuse identities retained by old color pickers.
            if paletteIDs.count != settings.palette.count {
                paletteIDs=settings.palette.map { _ in UUID() }
            }
        }
    }
    @Published var sourceImage: NSImage?
    @Published var hasCropSelection=false
    @Published var sourceName=""
    @Published var prepared: PixelImage?
    @Published var preparedImage: NSImage?
    @Published var resultImage: NSImage?
    @Published var project: BraidProject?
    @Published private(set) var tilePreviews: [TilePreview]=[]
    enum Activity { case preparingImage, extractingPalette, exclusive }
    @Published private(set) var activity: Activity?
    var busy: Bool { activity != nil }
    // Routine previews and extraction must not dim every control in the editor.
    var blocksEditing: Bool { activity == .exclusive }
    @Published var status="Choose a picture to begin."
    @Published var progress=0.0
    @Published var error: String?
    let solverURL=CBCRunner.discover()
    @Published var selectedTab=0
    @Published var paletteCount=6
    @Published var paletteSeparation=PaletteSeparation.medium
    @Published var paletteIncludeAccents=true
    @Published var exportTileSize=50
    @Published var zoom=1.0
    @Published var curves: BraidCurves?
    @Published var meshes: [TubeMesh]=[]
    @Published var curveGeneration=0
    @Published var sceneSettings=SceneSettings()
    @Published var cameraReset=0
    @Published var obliqueCamera=false
    @Published var exportProgress: ExportProgress?
    @Published var pictureExportSize:PictureExportSize = .viewport
    // Camera gestures do not need to invalidate SwiftUI on every mouse movement.
    private(set) var cameraState:CameraState?
    private weak var threeDView:BraidMetalView?
    private var sourceURL: URL?
    private var task: Task<Void,Never>?
    private var previewTask: Task<Void,Never>?
    private var preparedSettings: BraidCore.Settings?
    private var revision=0
    private var cachedTileData: TileData?
    private var paletteIDs=BraidCore.Settings().palette.map { _ in UUID() }
    private var exportSavePanel: NSSavePanel?
    var gpuName: String { MTLCreateSystemDefaultDevice()?.name ?? "CPU fallback" }
    var tileData: TileData { TileData(settings:settings) }
    var preparedIsCurrent: Bool { prepared != nil && preparedSettings?.hasSameImagePreparation(as:settings) == true }
    var resultNeedsWeaving: Bool {
        guard var solved=project?.settings else { return false }
        // The threshold affects the next Extract, not an existing weave.
        solved.backgroundMinimumDistance=settings.backgroundMinimumDistance
        return solved != settings
    }
    init() { refreshTiles() }

    var paletteEntries: [PaletteEntry] {
        zip(paletteIDs,settings.palette).enumerated().map { index,pair in
            PaletteEntry(id:pair.0,index:index,color:pair.1)
        }
    }
    func paletteColorBinding(for entry: PaletteEntry) -> Binding<Color> {
        Binding(get: {
            guard let index=self.paletteIDs.firstIndex(of:entry.id),self.settings.palette.indices.contains(index) else { return entry.color.color }
            return self.settings.palette[index].color
        },set: { color in
            guard let index=self.paletteIDs.firstIndex(of:entry.id),self.settings.palette.indices.contains(index) else { return }
            self.settings.palette[index]=RGB(color:color)
        })
    }
    func removePaletteColor(_ entry: PaletteEntry) {
        guard settings.palette.count>1,let index=paletteIDs.firstIndex(of:entry.id),settings.palette.indices.contains(index) else { return }
        settings.palette.remove(at:index)
    }
    func replacePalette(_ palette: [RGB]) {
        // Also invalidate old controls when replacement keeps the same number of colors.
        paletteIDs=palette.map { _ in UUID() }
        settings.palette=palette
    }

    func chooseImage() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.image,.json,.braidArtProject];panel.allowsMultipleSelection=false
        if panel.runModal() == .OK,let url=panel.url { open(url:url) }
    }
    func open(url: URL) {
        guard !busy else { return }
        task?.cancel();previewTask?.cancel();revision+=1
        if url.pathExtension.lowercased()=="braidart" || url.pathExtension.lowercased()=="json" { loadProject(url);return }
        activity = .exclusive;status="Opening image…";let rev=revision
        task=Task {
            do {
                let image=try await Task.detached { try ImageProcessor.thumbnail(url:url) }.value
                guard rev==revision else { return }
                sourceURL=url;sourceName=url.lastPathComponent;sourceImage=image.nsImage;clearCrop()
                prepared=nil;preparedImage=nil;project=nil;resultImage=nil;curves=nil;meshes=[];cameraState=nil;selectedTab=0;activity=nil
                prepare()
            } catch { fail(error) }
        }
    }
    func settingsChanged() {
        previewTask?.cancel();revision+=1
        refreshTiles()
        // Saved result keeps its own immutable settings; show it as a previous result.
        guard sourceURL != nil, !preparedIsCurrent else { return }
        let rev=revision
        previewTask=Task {
            try? await Task.sleep(nanoseconds:250_000_000)
            guard !Task.isCancelled, rev==revision,!busy,!preparedIsCurrent else { return }
            prepare()
        }
    }
    var cropAspectRatio: Double? {
        sourceImage.flatMap { CropGeometry.normalizedAspectRatio(for:settings.cropAspectRatio,imageSize:$0.size) }
    }
    func setCropAspectRatio(_ preset:PictureExportSize?) {
        settings.cropAspectRatio=preset
        guard sourceImage != nil,hasCropSelection || preset != nil else { return }
        settings.crop=CropGeometry.fitted(hasCropSelection ? settings.crop : Crop(),aspectRatio:cropAspectRatio)
        hasCropSelection=true
    }
    func scaleCrop(by factor:Double) {
        guard hasCropSelection,!blocksEditing else { return }
        settings.crop=CropGeometry.scaled(settings.crop,by:factor)
    }
    func clearCrop() {
        hasCropSelection=false;settings.crop=Crop()
    }
    func refreshTiles() {
        guard (try? settings.validate()) != nil else { return }
        let data=tileData
        guard data != cachedTileData else { return }
        cachedTileData=data
        tilePreviews=data.allTiles.compactMap { tile in
            guard let image=try? TileRenderer.tile(tile,data:data,size:64).nsImage else { return nil }
            return TilePreview(tile:tile,image:image)
        }
    }
    func prepare() {
        guard let url=sourceURL,!busy else { return }
        let snapshot=settings
        activity = .preparingImage;status="Preparing image…"
        task=Task {
            do {
                let image=try await Task.detached { try ImageProcessor.prepare(url:url,settings:snapshot) }.value
                guard !Task.isCancelled else { activity=nil;return }
                // Discard an obsolete preview before publishing any pixels.
                guard snapshot.hasSameImagePreparation(as:settings) else { activity=nil;prepare();return }
                prepared=image;preparedSettings=snapshot;preparedImage=try ImageProcessor.cgImage(image).nsImage
                status="\(image.width) × \(image.height) tiles · \(tileData.allTiles.count) candidates per tile";activity=nil
            } catch { fail(error) }
        }
    }
    func extractPalette() {
        guard let image=prepared,!busy else { return }
        activity = .extractingPalette;status="Finding strand and background colors…";let count=paletteCount,separation=paletteSeparation.minimumDistance
        let includeAccents=paletteIncludeAccents,url=sourceURL,snapshot=settings,current=preparedIsCurrent
        task=Task {
            do {
                let extracted=try await Task.detached {
                    // A click immediately after an adjustment must use the latest
                    // crop/contrast/grayscale, even before its debounced preview.
                    var target=image
                    if !current,let url { target=try ImageProcessor.prepare(url:url,settings:snapshot) }
                    if snapshot.grayscale { target.pixels=target.pixels.map(BackgroundExtractor.neutral) }
                    let palette:[RGB]
                    if includeAccents {
                        var detailed=try url.map { try ImageProcessor.preparePalette(url:$0,settings:snapshot) } ?? target
                        if snapshot.grayscale { detailed.pixels=detailed.pixels.map(BackgroundExtractor.neutral) }
                        palette=PaletteExtractor.distinctColors(in:detailed,count:count,minimumDistance:separation)
                    } else {
                        palette=PaletteExtractor.dominantColors(in:target,count:count,minimumDistance:separation)
                    }
                    var fitted=snapshot;fitted.palette=palette
                    return try BackgroundExtractor.matching(target,settings:fitted)
                }.valueWithCancellation()
                try Task.checkCancellation()
                replacePalette(extracted.palette);settings.background=extracted.background
                activity=nil;status="Extracted \(extracted.palette.count) of up to \(count) strand colors and fitted the background. Edit the colors below."
                settingsChanged()
            } catch is CancellationError {
                activity=nil;status="Color extraction cancelled. Previous colors retained."
            } catch { fail(error) }
        }
    }
    func solve() {
        guard !busy,let image=prepared,let executable=solverURL else { return }
        let snapshot=settings,name=sourceName
        activity = .exclusive;progress=0;selectedTab=2;status="Starting solver…"
        previewTask?.cancel()
        task=Task {
            do {
                let output=try await Task.detached(priority:.userInitiated) {
                    try await PartitionSolver.solve(image:image,settings:snapshot,executable:executable) { p,message in
                        await self.update(p,message)
                    }
                }.valueWithCancellation()
                try Task.checkCancellation()
                let result=output.1,data=output.0
                let rendered=try await Task.detached{try TileRenderer.render(solution:result.solution,data:data,tileSize:min(40,max(8,3200/max(image.width,image.height))))}.value
                let generated=try await Task.detached { try CurveGenerator.generate(solution:result.solution,data:data) }.value
                let tubes=try await Task.detached { try TubeMesher.build(generated) }.value
                cameraState=nil;curves=generated;meshes=tubes;curveGeneration+=1
                sceneSettings=SceneSettings(planeColor:data.background)
                project=BraidProject(sourceName:name,settings:snapshot,sampledImage:image,tileData:data,result:result)
                project?.sceneSettings=sceneSettings
                resultImage=rendered.nsImage;zoom=1;activity=nil;progress=1
                let quality=result.allPartitionsOptimal ? "Every part proven optimal" : "Feasible result · some parts reached the time or gap limit"
                status="\(quality) · \(String(format:"%.1f",result.elapsedSeconds)) s"
            } catch is CancellationError { activity=nil;status="Cancelled. Previous result retained." }
            catch { fail(error) }
        }
    }
    private func update(_ p: Double,_ message: String) { progress=p;status=message }
    func cancel() {
        if let exportProgress { exportProgress.cancelling=true;exportProgress.message="Cancelling export…" }
        task?.cancel();previewTask?.cancel()
    }
    private func fail(_ err: Error) { activity=nil;error=err.localizedDescription;status="Could not complete the operation." }
    func saveProject() {
        guard let project=projectForSaving,!busy else { return }
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName).braidart";panel.allowedContentTypes=[.braidArtProject];panel.isExtensionHidden=false
        if panel.runModal() == .OK,let url=panel.url {
            do { try project.save(to:url);status="Saved \(url.lastPathComponent)" } catch { fail(error) }
        }
    }
    var projectForSaving:BraidProject? {
        guard var saved=project else { return nil }
        // This is an extraction preference, so saving it does not replace the
        // colors or geometry associated with the existing woven result.
        saved.settings.backgroundMinimumDistance=settings.backgroundMinimumDistance
        saved.sceneSettings=sceneSettings;saved.cameraState=cameraState;saved.pictureExportSize=pictureExportSize
        return saved
    }
    private func loadProject(_ url: URL) {
        activity = .exclusive;status="Opening project…"
        task=Task {
            do {
                let loaded=try await Task.detached { try BraidProject.load(from:url) }.value
                let rendered=try await Task.detached{try TileRenderer.render(solution:loaded.result.solution,data:loaded.tileData,tileSize:min(40,max(8,3200/max(loaded.sampledImage.width,loaded.sampledImage.height))))}.value
                let generated=try await Task.detached { try CurveGenerator.generate(solution:loaded.result.solution,data:loaded.tileData) }.value
                let tubes=try await Task.detached { try TubeMesher.build(generated) }.value
                curves=generated;meshes=tubes;curveGeneration+=1
                sceneSettings=loaded.sceneSettings ?? SceneSettings(planeColor:loaded.tileData.background)
                cameraState=loaded.cameraState;pictureExportSize=loaded.pictureExportSize ?? .viewport
                paletteIDs=loaded.settings.palette.map { _ in UUID() }
                sourceURL=nil;sourceImage=nil;sourceName=loaded.sourceName;settings=loaded.settings
                hasCropSelection=loaded.settings.crop != Crop()
                prepared=loaded.sampledImage;preparedSettings=loaded.settings;preparedImage=try ImageProcessor.cgImage(loaded.sampledImage).nsImage
                project=loaded;resultImage=rendered.nsImage;refreshTiles();selectedTab=loaded.cameraState == nil ? 2 : 3;activity=nil
                status="Project restored · \(loaded.sampledImage.width) × \(loaded.sampledImage.height) tiles"
            } catch { fail(error) }
        }
    }
    func exportPNG() {
        guard let project=project,!busy else { return }
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName)-braid.png";panel.allowedContentTypes=[.png]
        guard panel.runModal() == .OK,let url=panel.url else { return }
        let size=exportTileSize;activity = .exclusive;status="Exporting PNG…"
        task=Task {
            do {
                try await Task.detached { let cg=try TileRenderer.render(solution:project.result.solution,data:project.tileData,tileSize:size);try ImageProcessor.writePNG(cg,to:url) }.value
                activity=nil;status="Saved \(url.lastPathComponent)"
            } catch { fail(error) }
        }
    }
    func exportData() {
        guard let project=projectForSaving,!busy else { return }
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.canCreateDirectories=true
        panel.message="Choose a parent folder for the solution, tile data and Wolfram export."
        guard panel.runModal() == .OK,let parent=panel.url else { return }
        var folder=parent.appendingPathComponent("\(baseName)-braid-data",isDirectory:true);var n=2
        while FileManager.default.fileExists(atPath:folder.path) { folder=parent.appendingPathComponent("\(baseName)-braid-data-\(n)",isDirectory:true);n+=1 }
        let destination=folder,size=exportTileSize;activity = .exclusive;status="Exporting solution and tiles…"
        task=Task {
            do {
                try await Task.detached { try ProjectExporter.export(project,to:destination,tileSize:size) }.value
                activity=nil;status="Exported \(destination.lastPathComponent)";NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { fail(error) }
        }
    }
    func sceneSettingsChanged() { project?.sceneSettings=sceneSettings }
    func resetCamera(oblique:Bool) { obliqueCamera=oblique;cameraReset+=1 }
    func cameraChanged(_ state:CameraState) { cameraState=state }
    func register3DView(_ view:BraidMetalView) { threeDView=view }
    func export3DPicture() {
        guard !busy,exportSavePanel == nil,selectedTab==3,curves != nil,let view=threeDView,let window=view.window else { return }
        let capture:BraidPictureCapture
        do { capture=try view.makePictureCapture() }
        catch { fail(error);return }
        let options=PictureExportOptions(size:pictureExportSize,viewport:view.viewportPixelSize) { [weak self] size in
            self?.pictureExportSize=size
        }
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName)-3d.png";panel.allowedContentTypes=[.png]
        panel.message="Export the current 3D picture."
        let accessory=NSHostingView(rootView:PictureExportOptionsView(options:options))
        accessory.setFrameSize(accessory.fittingSize);panel.accessoryView=accessory
        exportSavePanel=panel
        panel.beginSheetModal(for:window) { [weak self] response in
            guard let self else { return }
            self.exportSavePanel=nil
            guard response == .OK,let url=panel.url,!self.busy else { return }
            self.pictureExportSize=options.size
            self.startPictureExport(capture,size:options.pixelSize,to:url)
        }
    }
    private func startPictureExport(_ capture:BraidPictureCapture,size:CGSize,to url:URL) {
        let export=ExportProgress(title:"Exporting 3D Picture",filename:url.lastPathComponent,message:"Rendering 3D picture…")
        activity = .exclusive;progress=0;status="Exporting 3D picture…";exportProgress=export
        task=Task {
            do {
                try await Task.detached(priority:.userInitiated) {
                    let image=try capture.render(size:size)
                    try Task.checkCancellation()
                    DispatchQueue.main.async {
                        guard !export.cancelling else { return }
                        export.progress=0.8;export.message="Saving PNG…"
                    }
                    // Encode beside the destination, then commit only the complete image.
                    let temporary=url.deletingLastPathComponent().appendingPathComponent(".braidart-\(UUID().uuidString).png")
                    defer { try? FileManager.default.removeItem(at:temporary) }
                    try ImageProcessor.writePNG(image,to:temporary)
                    try Task.checkCancellation()
                    try Data(contentsOf:temporary).write(to:url,options:.atomic)
                }.valueWithCancellation()
                exportProgress=nil;activity=nil;progress=1;status="Saved \(url.lastPathComponent)"
            } catch is CancellationError {
                exportProgress=nil;activity=nil;progress=0;status="Picture export cancelled."
            } catch {
                exportProgress=nil;fail(error)
            }
        }
    }
    func exportPDF() {
        guard curves != nil,!busy,exportSavePanel == nil else { return }
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName)-braid.pdf";panel.allowedContentTypes=[.pdf]
        exportSavePanel=panel
        let completion: (NSApplication.ModalResponse)->Void = { [weak self] response in
            guard let self else { return }
            self.exportSavePanel=nil
            guard response == .OK,let url=panel.url,let curves=self.curves,!self.busy else { return }
            self.startPDFExport(curves,to:url)
        }
        if let window=NSApp.keyWindow { panel.beginSheetModal(for:window,completionHandler:completion) }
        else { panel.begin(completionHandler:completion) }
    }
    private func startPDFExport(_ curves:BraidCurves,to url:URL) {
        let export=ExportProgress(title:"Exporting PDF",filename:url.lastPathComponent,message:"Preparing vector PDF…")
        activity = .exclusive;progress=0;status="Exporting vector PDF…";exportProgress=export
        task=Task {
            do {
                try await Task.detached(priority:.userInitiated) {
                    try CurveExporter.writePDF(curves,to:url) { value,message in
                        DispatchQueue.main.async {
                            guard !export.cancelling else { return }
                            export.progress=value;export.message=message
                        }
                    }
                }.valueWithCancellation()
                exportProgress=nil;activity=nil;progress=1;status="Saved \(url.lastPathComponent)"
            } catch is CancellationError {
                exportProgress=nil;activity=nil;progress=0;status="PDF export cancelled."
            } catch {
                exportProgress=nil;fail(error)
            }
        }
    }
    func exportGLB() {
        guard let curves,!busy else { return }
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName)-braid.glb";panel.allowedContentTypes=[UTType(filenameExtension:"glb") ?? .data]
        guard panel.runModal() == .OK,let url=panel.url else { return }
        let all=meshes+[TubeMesher.plane(curves,settings:sceneSettings)]
        runExport("Exporting colored 3D object…",success:"Saved \(url.lastPathComponent)") { try GLBExporter.write(meshes:all,to:url) }
    }
    func exportUSDZ() {
        guard let curves,!busy,exportSavePanel == nil else { return }
        let all=meshes+[TubeMesher.plane(curves,settings:sceneSettings)]
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName)-braid.usdz"
        panel.allowedContentTypes=[UTType(filenameExtension:"usdz") ?? .data]
        panel.message="Export a colored 3D object for Apple Motion."
        exportSavePanel=panel
        let completion:(NSApplication.ModalResponse)->Void = { [weak self] response in
            guard let self else { return }
            self.exportSavePanel=nil
            guard response == .OK,let url=panel.url,!self.busy else { return }
            self.startUSDZExport(all,to:url)
        }
        if let window=NSApp.keyWindow { panel.beginSheetModal(for:window,completionHandler:completion) }
        else { panel.begin(completionHandler:completion) }
    }
    private func startUSDZExport(_ meshes:[TubeMesh],to url:URL) {
        let export=ExportProgress(title:"Exporting USDZ",filename:url.lastPathComponent,message:"Preparing USDZ geometry…")
        activity = .exclusive;progress=0;status="Exporting USDZ 3D object…";exportProgress=export
        task=Task {
            do {
                try await Task.detached(priority:.userInitiated) {
                    try USDZExporter.write(meshes:meshes,to:url) { value,message in
                        DispatchQueue.main.async {
                            guard !export.cancelling else { return }
                            export.progress=value;export.message=message
                        }
                    }
                }.valueWithCancellation()
                exportProgress=nil;activity=nil;progress=1;status="Saved \(url.lastPathComponent)"
            } catch is CancellationError {
                exportProgress=nil;activity=nil;progress=0;status="USDZ export cancelled."
            } catch {
                exportProgress=nil;fail(error)
            }
        }
    }
    private func runExport(_ message:String,success:String,operation:@escaping @Sendable () throws -> Void) {
        activity = .exclusive;status=message
        task=Task {
            do { try await Task.detached(priority:.userInitiated) { try operation() }.value;activity=nil;status=success }
            catch { fail(error) }
        }
    }
    private var baseName: String { (sourceName as NSString).deletingPathExtension.isEmpty ? "BraidArt" : (sourceName as NSString).deletingPathExtension }
}

extension Task where Failure == Error {
    func valueWithCancellation() async throws -> Success {
        try await withTaskCancellationHandler { try await value } onCancel: { cancel() }
    }
}
