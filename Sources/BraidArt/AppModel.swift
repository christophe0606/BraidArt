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

@MainActor
final class AppModel: ObservableObject {
    @Published var settings=BraidCore.Settings()
    @Published var sourceImage: NSImage?
    @Published var sourceName=""
    @Published var prepared: PixelImage?
    @Published var preparedImage: NSImage?
    @Published var resultImage: NSImage?
    @Published var project: BraidProject?
    @Published var tileImages: [NSImage]=[]
    @Published var busy=false
    @Published var status="Choose a picture to begin."
    @Published var progress=0.0
    @Published var error: String?
    @Published var solverURL=CBCRunner.discover()
    @Published var selectedTab=0
    @Published var paletteCount=4
    @Published var exportTileSize=50
    @Published var zoom=1.0
    @Published var curves: BraidCurves?
    @Published var meshes: [TubeMesh]=[]
    @Published var curveGeneration=0
    @Published var sceneSettings=SceneSettings()
    @Published var cameraReset=0
    @Published var obliqueCamera=false
    @Published var exportProgress: ExportProgress?
    private weak var threeDView:BraidMetalView?
    private var sourceURL: URL?
    private var task: Task<Void,Never>?
    private var previewTask: Task<Void,Never>?
    private var preparedSettings: BraidCore.Settings?
    private var revision=0
    private var cachedTileData: TileData?
    private var exportSavePanel: NSSavePanel?
    private var pictureExportSize:PictureExportSize = .viewport
    var gpuName: String { MTLCreateSystemDefaultDevice()?.name ?? "CPU fallback" }
    var tileData: TileData { TileData(settings:settings) }
    var preparedIsCurrent: Bool { prepared != nil && preparedSettings?.hasSameImagePreparation(as:settings) == true }
    init() { refreshTiles() }

    func chooseImage() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.image,.json,UTType(filenameExtension:"braidart") ?? .json];panel.allowsMultipleSelection=false
        if panel.runModal() == .OK,let url=panel.url { open(url:url) }
    }
    func open(url: URL) {
        guard !busy else { return }
        task?.cancel();previewTask?.cancel();revision+=1
        if url.pathExtension.lowercased()=="braidart" || url.pathExtension.lowercased()=="json" { loadProject(url);return }
        busy=true;status="Opening image…";let rev=revision
        task=Task {
            do {
                let image=try await Task.detached { try ImageProcessor.thumbnail(url:url) }.value
                guard rev==revision else { return }
                sourceURL=url;sourceName=url.lastPathComponent;sourceImage=image.nsImage;settings.crop=Crop()
                prepared=nil;preparedImage=nil;project=nil;resultImage=nil;curves=nil;meshes=[];selectedTab=0;busy=false
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
            guard !Task.isCancelled, rev==revision,!busy else { return }
            prepare()
        }
    }
    func refreshTiles() {
        guard (try? settings.validate()) != nil else { return }
        let data=tileData
        guard data != cachedTileData else { return }
        cachedTileData=data
        tileImages=data.allTiles.compactMap{try? TileRenderer.tile($0,data:data,size:64).nsImage}
    }
    func prepare() {
        guard let url=sourceURL,!busy else { return }
        let snapshot=settings,rev=revision
        busy=true;status="Preparing image…"
        task=Task {
            do {
                let image=try await Task.detached { try ImageProcessor.prepare(url:url,settings:snapshot) }.value
                guard !Task.isCancelled else { busy=false;return }
                prepared=image;preparedSettings=snapshot;preparedImage=try ImageProcessor.cgImage(image).nsImage
                status="\(image.width) × \(image.height) tiles · \(tileData.allTiles.count) candidates per tile";busy=false
                if rev != revision { prepare() }
            } catch { fail(error) }
        }
    }
    func extractPalette() {
        guard let image=prepared,!busy else { return }
        busy=true;status="Finding dominant colors…";let count=paletteCount
        task=Task {
            let palette=await Task.detached{PaletteExtractor.dominantColors(in:image,count:count)}.value
            settings.palette=palette;busy=false;status="Palette extracted. Edit its colors below."
            settingsChanged()
        }
    }
    func solve() {
        guard !busy,let image=prepared,let executable=solverURL else { return }
        let snapshot=settings,name=sourceName
        busy=true;progress=0;selectedTab=2;status="Starting solver…"
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
                curves=generated;meshes=tubes;curveGeneration+=1
                sceneSettings=SceneSettings(planeColor:data.background)
                project=BraidProject(sourceName:name,settings:snapshot,sampledImage:image,tileData:data,result:result)
                project?.sceneSettings=sceneSettings
                resultImage=rendered.nsImage;zoom=1;busy=false;progress=1
                let quality=result.allPartitionsOptimal ? "Every part proven optimal" : "Feasible result · some parts reached the time or gap limit"
                status="\(quality) · \(String(format:"%.1f",result.elapsedSeconds)) s"
            } catch is CancellationError { busy=false;status="Cancelled. Previous result retained." }
            catch { fail(error) }
        }
    }
    private func update(_ p: Double,_ message: String) { progress=p;status=message }
    func cancel() {
        if let exportProgress { exportProgress.cancelling=true;exportProgress.message="Cancelling export…" }
        task?.cancel();previewTask?.cancel()
    }
    private func fail(_ err: Error) { busy=false;error=err.localizedDescription;status="Could not complete the operation." }
    func selectSolver() {
        let panel=NSOpenPanel();panel.message="Choose the COIN-OR CBC executable";panel.allowsMultipleSelection=false
        if panel.runModal() == .OK,let url=panel.url { solverURL=url }
    }
    func saveProject() {
        guard let project=project,!busy else { return }
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName).braidart";panel.allowedContentTypes=[UTType(filenameExtension:"braidart") ?? .json]
        if panel.runModal() == .OK,let url=panel.url {
            do { try project.save(to:url);status="Saved \(url.lastPathComponent)" } catch { fail(error) }
        }
    }
    private func loadProject(_ url: URL) {
        busy=true;status="Opening project…"
        task=Task {
            do {
                let loaded=try await Task.detached { try BraidProject.load(from:url) }.value
                let rendered=try await Task.detached{try TileRenderer.render(solution:loaded.result.solution,data:loaded.tileData,tileSize:min(40,max(8,3200/max(loaded.sampledImage.width,loaded.sampledImage.height))))}.value
                let generated=try await Task.detached { try CurveGenerator.generate(solution:loaded.result.solution,data:loaded.tileData) }.value
                let tubes=try await Task.detached { try TubeMesher.build(generated) }.value
                curves=generated;meshes=tubes;curveGeneration+=1
                sceneSettings=loaded.sceneSettings ?? SceneSettings(planeColor:loaded.tileData.background)
                sourceURL=nil;sourceImage=nil;sourceName=loaded.sourceName;settings=loaded.settings
                prepared=loaded.sampledImage;preparedSettings=loaded.settings;preparedImage=try ImageProcessor.cgImage(loaded.sampledImage).nsImage
                project=loaded;resultImage=rendered.nsImage;refreshTiles();selectedTab=2;busy=false
                status="Project restored · \(loaded.sampledImage.width) × \(loaded.sampledImage.height) tiles"
            } catch { fail(error) }
        }
    }
    func exportPNG() {
        guard let project=project,!busy else { return }
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName)-braid.png";panel.allowedContentTypes=[.png]
        guard panel.runModal() == .OK,let url=panel.url else { return }
        let size=exportTileSize;busy=true;status="Exporting PNG…"
        task=Task {
            do {
                try await Task.detached { let cg=try TileRenderer.render(solution:project.result.solution,data:project.tileData,tileSize:size);try ImageProcessor.writePNG(cg,to:url) }.value
                busy=false;status="Saved \(url.lastPathComponent)"
            } catch { fail(error) }
        }
    }
    func exportData() {
        guard let project=project,!busy else { return }
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.canCreateDirectories=true
        panel.message="Choose a parent folder for the solution, tile data and Wolfram export."
        guard panel.runModal() == .OK,let parent=panel.url else { return }
        var folder=parent.appendingPathComponent("\(baseName)-braid-data",isDirectory:true);var n=2
        while FileManager.default.fileExists(atPath:folder.path) { folder=parent.appendingPathComponent("\(baseName)-braid-data-\(n)",isDirectory:true);n+=1 }
        let destination=folder,size=exportTileSize;busy=true;status="Exporting solution and tiles…"
        task=Task {
            do {
                try await Task.detached { try ProjectExporter.export(project,to:destination,tileSize:size) }.value
                busy=false;status="Exported \(destination.lastPathComponent)";NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { fail(error) }
        }
    }
    func sceneSettingsChanged() { project?.sceneSettings=sceneSettings }
    func resetCamera(oblique:Bool) { obliqueCamera=oblique;cameraReset+=1 }
    func register3DView(_ view:BraidMetalView) { threeDView=view }
    func export3DPicture() {
        guard !busy,exportSavePanel == nil,selectedTab==3,curves != nil,let view=threeDView,let window=view.window else { return }
        let options=PictureExportOptions(size:pictureExportSize,viewport:view.viewportPixelSize)
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
            do { self.startPictureExport(try view.makePictureCapture(size:options.pixelSize),to:url) }
            catch { self.fail(error) }
        }
    }
    private func startPictureExport(_ capture:BraidPictureCapture,to url:URL) {
        let export=ExportProgress(title:"Exporting 3D Picture",filename:url.lastPathComponent,message:"Rendering 3D picture…")
        busy=true;progress=0;status="Exporting 3D picture…";exportProgress=export
        task=Task {
            do {
                try await Task.detached(priority:.userInitiated) {
                    let image=try capture.render()
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
                exportProgress=nil;busy=false;progress=1;status="Saved \(url.lastPathComponent)"
            } catch is CancellationError {
                exportProgress=nil;busy=false;progress=0;status="Picture export cancelled."
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
        busy=true;progress=0;status="Exporting vector PDF…";exportProgress=export
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
                exportProgress=nil;busy=false;progress=1;status="Saved \(url.lastPathComponent)"
            } catch is CancellationError {
                exportProgress=nil;busy=false;progress=0;status="PDF export cancelled."
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
    private func runExport(_ message:String,success:String,operation:@escaping @Sendable () throws -> Void) {
        busy=true;status=message
        task=Task {
            do { try await Task.detached(priority:.userInitiated) { try operation() }.value;busy=false;status=success }
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
