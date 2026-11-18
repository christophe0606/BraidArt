import SwiftUI
import CoreTransferable
#if os(macOS)
import AppKit
import PhotosUI
#else
import UIKit
#endif
import UniformTypeIdentifiers
import Metal
import BraidCore

extension RGB {
    var color: Color { Color(.sRGB,red:r,green:g,blue:b,opacity:1) }
    init(color: Color) {
        #if os(macOS)
        let c=NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(c.redComponent,c.greenComponent,c.blueComponent)
        #else
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        UIColor(color).getRed(&r,green:&g,blue:&b,alpha:&a)
        self.init(Double(r),Double(g),Double(b))
        #endif
    }
}


struct PaletteEntry: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let color: RGB
}

struct TilePreview: Identifiable {
    let tile: Tile
    let image: PlatformImage
    var id: Int { tile.id }
}

enum PaletteSeparation: String, CaseIterable, Identifiable {
    case keepShades="Keep shades", low="Low", medium="Medium", high="High"
    var id: Self { self }
    var title: String { L(rawValue) }
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

enum DimensionSelectionTarget:String,Identifiable {
    case output,picture
    var id:String { rawValue }
}

/// Owns the local copy of a photo for the lifetime of the editor's source.
final class ImportedPhoto: Transferable {
    let url: URL

    init(owning url: URL) { self.url = url }

    init(copying file: URL) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BraidImport-\(UUID().uuidString)")
        let destination = folder.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: file, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        url = destination
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { try ImportedPhoto(copying: $0.file) }
    }

    deinit { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

private enum PictureInput: @unchecked Sendable {
    case image(URL),frame(CGImage)
    func prepare(settings:BraidCore.Settings) throws -> PixelImage {
        switch self {
        case .image(let url): return try ImageProcessor.prepare(url:url,settings:settings)
        case .frame(let image): return try ImageProcessor.prepare(image:image,settings:settings)
        }
    }
    func preparePalette(settings:BraidCore.Settings) throws -> PixelImage {
        switch self {
        case .image(let url): return try ImageProcessor.preparePalette(url:url,settings:settings)
        case .frame(let image): return try ImageProcessor.preparePalette(image:image,settings:settings)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings:BraidCore.Settings = {
        var settings=BraidCore.Settings();settings.grayscale=true
        return settings
    }() {
        didSet {
            // A resized palette must not reuse identities retained by old color pickers.
            if paletteIDs.count != settings.palette.count {
                paletteIDs=settings.palette.map { _ in UUID() }
            }
        }
    }
    @Published var sourceImage: PlatformImage?
    @Published private(set) var videoSource:VideoSource?
    @Published private(set) var videoFrameTime=0.0
    @Published private(set) var selectedFrameTime=0.0
    @Published private(set) var selectingVideoFrame=false
    @Published var videoFormat=VideoOutputFormat.mostCompatible
    @Published var videoIncludeAudio=true { didSet { videoPlayback?.player.isMuted = !videoIncludeAudio } }
    @Published private(set) var videoSegment:VideoSegment?
    @Published private(set) var videoPlayback:VideoPlayback?
    @Published private(set) var isPlayingVideo=false
    private enum FrameAction { case none,weave,extract }
    private var nextFrameAction=FrameAction.none
    private var checkedFrameTime:Double?
    private var videoFrame:CGImage?
    private var frameSelectionID=0
    private var preparedFrameID:Int?
    private var checkedVideoSettings:BraidCore.Settings?
    @Published var hasCropSelection=false
    @Published var sourceName=""
    @Published var prepared: PixelImage?
    @Published var preparedImage: PlatformImage?
    @Published var resultImage: PlatformImage?
    @Published var project: BraidProject?
    @Published private(set) var tilePreviews: [TilePreview]=[]
    enum Activity { case preparingImage, extractingPalette, exclusive }
    @Published private(set) var activity: Activity?
    @Published private var activeToneSliders = Set<KeyPath<BraidCore.Settings, Double>>()
    var busy: Bool { activity != nil }
    // Routine previews and extraction must not dim every control in the editor.
    var blocksEditing: Bool { activity == .exclusive }
    @Published var status=L("Choose an image or video to begin.")
    @Published var progress=0.0
    @Published var error: String?
    @Published var selectedTab=0
    @Published var paletteCount=6
    @Published var paletteSeparation=PaletteSeparation.medium
    @Published var paletteIncludeAccents=true
    @Published var zoom=1.0
    @Published var curves: BraidCurves?
    @Published var meshes: [TubeMesh]=[]
    @Published var curveGeneration=0
    @Published var sceneSettings=SceneSettings()
    @Published var cameraReset=0
    @Published var exportProgress: ExportProgress?
    @Published private var selectedPictureSize: PictureExportSize?
    var pictureExportSize: PictureExportSize {
        get { selectedPictureSize ?? settings.outputSize }
        set { selectedPictureSize = newValue == .viewport ? nil : newValue }
    }
    @Published private(set) var customDimensions:[PictureExportSize]=[]
    @Published var dimensionManagerTarget:DimensionSelectionTarget?
    private let defaults:UserDefaults
    private static let customDimensionsKey="customOutputDimensions"
    // Camera gestures do not need to invalidate SwiftUI on every mouse movement.
    private(set) var cameraState:CameraState?
    private weak var threeDView:BraidMetalView?
    private var importedPhoto: ImportedPhoto?
    private var sourceURL: URL? {
        didSet { if sourceURL != importedPhoto?.url { importedPhoto = nil } }
    }
    private var weavingState:PartitionExecutionControl.Snapshot?
    private var weavingMessage=""
    #if os(iOS)
    var isWeaving: Bool { weavingState != nil }
    private lazy var weavingLifecycle=MobileWeavingLifecycle { [weak self] state in
        guard let self else { return }
        self.weavingState=state
        self.refreshWeavingStatus()
        #if DEBUG
        self.publishBackgroundWeavingTestValue()
        #endif
    }
    #if DEBUG
    @Published private(set) var backgroundWeavingTestValue: String?
    private static let tracesBackgroundWeaving = ProcessInfo.processInfo.arguments.contains("--trace-background-weaving")

    private func publishBackgroundWeavingTestValue() {
        guard Self.tracesBackgroundWeaving else { return }
        let lifecycle = weavingLifecycle
        let value = "part=\(weavingState?.currentPartition ?? 0) pausedPart=\(lifecycle.testPausedPart) completed=\(lifecycle.testCompletedPart) resumedPart=\(lifecycle.testResumedPart) continued=\(lifecycle.testUsedContinued)"
        if value != backgroundWeavingTestValue { backgroundWeavingTestValue = value }
    }
    #endif
    #endif
    private var task: Task<Void,Never>?
    private var previewTask: Task<Void,Never>?
    private var preparedSettings: BraidCore.Settings?
    private var revision=0
    private var cachedTileData: TileData?
    private var paletteIDs=BraidCore.Settings().palette.map { _ in UUID() }
    @Published var showingPhotoImport=false
    #if os(macOS)
    private var exportSavePanel: NSSavePanel?
    #else
    @Published var showingImportChoice=false
    @Published var showingFileImport=false
    @Published var exportedFile:MobileExportFile?
    private var mobileExportDirectory: URL?
    #endif
    var gpuName: String { MTLCreateSystemDefaultDevice()?.name ?? L("CPU fallback") }
    var tileData: TileData { TileData(settings:settings) }
    var canChangeOutputDimensions: Bool { sourceImage != nil || project == nil }
    var preparedIsCurrent: Bool {
        prepared != nil && preparedSettings?.hasSameImagePreparation(as:settings) == true &&
        (videoSource == nil || (!isPlayingVideo && !selectingVideoFrame && preparedFrameID==frameSelectionID))
    }
    var canWeavePicture:Bool {
        activeToneSliders.isEmpty && !busy && (try? settings.validate()) != nil &&
        (preparedIsCurrent || (videoSource != nil && !selectingVideoFrame))
    }
    var canWeaveVideo:Bool {
        guard videoSource != nil,!busy,var checked=checkedVideoSettings,let segment=videoSegment,let time=checkedFrameTime,
              time>=segment.start,time<segment.end else { return false }
        checked.backgroundMinimumDistance=settings.backgroundMinimumDistance
        return checked==settings && (try? VideoWeaver.validate(settings:settings)) != nil
    }
    private var pictureInput:PictureInput? {
        if videoSource != nil { return videoFrame.map(PictureInput.frame) }
        return sourceURL.map(PictureInput.image)
    }
    var resultNeedsWeaving: Bool {
        guard let project else { return false }
        return project.settings.outputPixelSize != settings.outputPixelSize || sculptureNeedsWeaving
    }
    var sculptureNeedsWeaving: Bool {
        guard var solved=project?.settings else { return false }
        // The threshold affects the next Extract, not an existing weave.
        solved.backgroundMinimumDistance=settings.backgroundMinimumDistance
        // The crop and sample affect the sculpture. The woven PNG pixel size does not.
        solved.outputSize=settings.outputSize
        return solved != settings
    }
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        if let data=defaults.data(forKey:Self.customDimensionsKey),
           let saved=try? JSONDecoder().decode([PictureExportSize].self,from:data) {
            var ids=Set<String>()
            customDimensions=saved.filter { $0.customSize != nil && ids.insert($0.id).inserted }
        }
        refreshTiles()
    }

    @discardableResult
    func addCustomDimensions(name:String,width:Int,height:Int) throws -> PictureExportSize {
        let preset=PictureExportSize.custom(try CustomPictureSize(name:name,width:width,height:height))
        customDimensions.append(preset);saveCustomDimensions()
        return preset
    }
    @discardableResult
    func editCustomDimensions(_ preset:PictureExportSize,name:String,width:Int,height:Int) throws -> PictureExportSize {
        guard let custom=preset.customSize,let index=customDimensions.firstIndex(where:{$0.id==preset.id}) else {
            throw BraidError.invalid(L("Only custom dimensions can be edited or deleted."))
        }
        let replacement=PictureExportSize.custom(try CustomPictureSize(id:custom.id,name:name,width:width,height:height))
        customDimensions[index]=replacement;saveCustomDimensions()
        if settings.outputSize.id==preset.id { setOutputSize(replacement) }
        if selectedPictureSize?.id==preset.id { selectedPictureSize=replacement }
        return replacement
    }
    @discardableResult
    func deleteCustomDimensions(_ preset:PictureExportSize)->Bool {
        guard preset.customSize != nil,customDimensions.contains(where:{$0.id==preset.id}) else { return false }
        customDimensions.removeAll { $0.id==preset.id };saveCustomDimensions()
        if settings.outputSize.id==preset.id { setOutputSize(.fullHD) }
        if selectedPictureSize?.id==preset.id { selectedPictureSize=nil }
        return true
    }
    private func saveCustomDimensions() {
        if let data=try? JSONEncoder().encode(customDimensions) { defaults.set(data,forKey:Self.customDimensionsKey) }
    }

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

    #if os(macOS)
    func chooseImage() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.image,.movie,.video,.json,.braidArtProject];panel.allowsMultipleSelection=false
        if panel.runModal() == .OK,let url=panel.url { open(url:url) }
    }
    func choosePhoto() {
        guard !busy else { return }
        showingPhotoImport = true
    }
    func importPhoto(_ item: PhotosPickerItem) {
        guard beginOpeningSource() else { return }
        openImage {
            guard let photo = try await item.loadTransferable(type: ImportedPhoto.self) else {
                throw BraidError.invalid(L("Cannot open the selected picture or video."))
            }
            return (photo.url, photo)
        }
    }
    #endif
    private func beginOpeningSource() -> Bool {
        guard !busy else { return false }
        task?.cancel();previewTask?.cancel();revision+=1
        return true
    }
    func open(url: URL) {
        guard beginOpeningSource() else { return }
        if url.pathExtension.lowercased()=="braidart" || url.pathExtension.lowercased()=="json" { loadProject(url);return }
        if VideoSource.isVideo(url) { openVideo(url);return }
        openImage { (url, nil) }
    }
    private func openImage(_ load: @escaping () async throws -> (URL, ImportedPhoto?)) {
        let previousStatus=status
        activity = .exclusive;status=L("Opening image…");let rev=revision
        task=Task {
            do {
                let (url, photo)=try await load()
                try Task.checkCancellation()
                let image=try await Task.detached { try ImageProcessor.thumbnail(url:url) }.valueWithCancellation()
                try Task.checkCancellation()
                guard rev==revision else { return }
                clearVideoSource()
                sourceURL=url;importedPhoto=photo;sourceName=url.lastPathComponent;sourceImage=image.platformImage;resetCrop()
                prepared=nil;preparedImage=nil;project=nil;resultImage=nil;curves=nil;meshes=[];cameraState=nil;selectedTab=0;activity=nil
                prepare()
            } catch is CancellationError {
                activity=nil;status=previousStatus
            } catch { fail(error) }
        }
    }
    private func clearVideoSource() {
        videoPlayback?.invalidate();videoPlayback=nil;videoSegment=nil;isPlayingVideo=false;nextFrameAction = .none;checkedFrameTime=nil
        videoSource=nil;videoFrame=nil;videoFrameTime=0;selectedFrameTime=0;selectingVideoFrame=false
        preparedFrameID=nil;checkedVideoSettings=nil;frameSelectionID+=1
    }
    private func openVideo(_ url:URL, ownedFile: ImportedPhoto? = nil) {
        activity = .exclusive;status=L("Opening video…")
        task=Task { [self] in
            do {
                let source=try await VideoSource.open(url:url)
                let frame=try await source.frame(at:0)
                try Task.checkCancellation()
                clearVideoSource();videoSource=source;videoFrame=frame.image;selectedFrameTime=frame.time
                let segment=try VideoSegment(start:0,end:source.duration)
                videoSegment=segment
                let playback=VideoPlayback(source:source,segment:segment)
                playback.player.isMuted = !videoIncludeAudio
                playback.onPlaybackChanged={ [weak self] playing in
                    guard let self else { return }
                    self.isPlayingVideo=playing
                    if playing { self.preparedFrameID=nil }
                }
                playback.onPaused={ [weak self] time in self?.selectVideoFrame(at:time) }
                videoPlayback=playback
                sourceURL=url;importedPhoto=ownedFile;sourceName=url.lastPathComponent;sourceImage=frame.image.platformImage;resetCrop()
                prepared=nil;preparedImage=nil;project=nil;resultImage=nil;curves=nil;meshes=[];cameraState=nil;selectedTab=0;activity=nil
                prepare()
            } catch is CancellationError { activity=nil;status=L("Cancelled. Previous result retained.") }
            catch { fail(error) }
        }
    }
    func selectVideoFrame(at time:Double) {
        nextFrameAction = .none
        selectVideoFrame(at:time,after:.none)
    }
    private func selectVideoFrame(at time:Double,after action:FrameAction) {
        guard let source=videoSource,time.isFinite,!blocksEditing,activity != .extractingPalette else { return }
        let time=min(source.lastPreviewTime,(videoSegment?.end ?? source.duration)-0.000001,max(videoSegment?.start ?? 0,time))
        videoPlayback?.seek(to:time)
        nextFrameAction=action
        task?.cancel();previewTask?.cancel();frameSelectionID+=1
        let selection=frameSelectionID
        videoFrameTime=time;selectingVideoFrame=true;activity = .preparingImage;status=L("Loading video frame…")
        task=Task {
            do {
                try await Task.sleep(for:.milliseconds(100))
                let frame=try await source.frame(at:time)
                try Task.checkCancellation()
                guard selection==frameSelectionID else { return }
                videoFrame=frame.image;selectedFrameTime=frame.time;sourceImage=frame.image.platformImage
                selectingVideoFrame=false;activity=nil;prepare()
            } catch is CancellationError {} catch {
                guard selection==frameSelectionID else { return }
                selectingVideoFrame=false;fail(error)
            }
        }
    }
    func setVideoSegment(start:Double,end:Double) {
        guard let source=videoSource,!blocksEditing,let segment=try? VideoSegment(start:start,end:end),
              (try? segment.validate(sourceDuration:source.duration)) != nil else { return }
        videoSegment=segment;videoPlayback?.setSegment(segment)
        if !isPlayingVideo {
            selectVideoFrame(at:min(end-0.000001,max(start,videoFrameTime)))
        }
    }
    func settingsChanged() {
        previewTask?.cancel();revision+=1
        refreshTiles()
        // Saved result keeps its own immutable settings; show it as a previous result.
        guard sourceURL != nil,!isPlayingVideo,!preparedIsCurrent else { return }
        if let preparedSettings, settings.hasSameCropAndResolution(as: preparedSettings) {
            prepare()
            return
        }
        let rev=revision
        previewTask=Task {
            try? await Task.sleep(nanoseconds:250_000_000)
            guard !Task.isCancelled, rev==revision,!busy,!preparedIsCurrent else { return }
            prepare()
        }
    }
    func setToneEditing(_ editing: Bool, for setting: KeyPath<BraidCore.Settings, Double>) {
        guard activeToneSliders.contains(setting) != editing else { return }
        if editing { activeToneSliders.insert(setting) }
        else { activeToneSliders.remove(setting) }
    }
    var cropAspectRatio: Double? {
        sourceImage.flatMap { CropGeometry.normalizedAspectRatio(for:settings.outputSize,imageSize:$0.size) }
    }
    func setOutputSize(_ preset:PictureExportSize) {
        guard canChangeOutputDimensions,preset != .viewport,preset != settings.outputSize else { return }
        let previousRatio=cropAspectRatio
        settings.outputSize=preset
        guard sourceImage != nil,previousRatio != cropAspectRatio else { return }
        settings.crop=CropGeometry.fitted(hasCropSelection ? settings.crop : Crop(),aspectRatio:cropAspectRatio)
        hasCropSelection=true
    }
    func scaleCrop(by factor:Double) {
        guard hasCropSelection,!blocksEditing else { return }
        settings.crop=CropGeometry.scaled(settings.crop,by:factor)
    }
    func resetCrop() {
        settings.crop=CropGeometry.fitted(Crop(),aspectRatio:cropAspectRatio)
        hasCropSelection=sourceImage != nil
    }
    func refreshTiles() {
        guard (try? settings.validate()) != nil else { return }
        let data=tileData
        guard data != cachedTileData else { return }
        cachedTileData=data
        tilePreviews=data.allTiles.compactMap { tile in
            guard let image=try? TileRenderer.tile(tile,data:data,size:64).platformImage else { return nil }
            return TilePreview(tile:tile,image:image)
        }
    }
    func prepare() {
        guard let input=pictureInput,!busy,!selectingVideoFrame,!isPlayingVideo else { return }
        let snapshot=settings,selection=frameSelectionID
        activity = .preparingImage;status=L("Preparing image…")
        task=Task {
            do {
                let (image, preview)=try await Task.detached {
                    let image=try input.prepare(settings:snapshot)
                    return (image, try ImageProcessor.cgImage(image))
                }.valueWithCancellation()
                guard !Task.isCancelled,selection==frameSelectionID else { return }
                if !snapshot.hasSameImagePreparation(as: settings) {
                    // Show intermediate tonal edits while dragging. Weave still
                    // waits for a sample that matches the current settings.
                    if snapshot.hasSameCropAndResolution(as: settings), !preparedIsCurrent {
                        preparedImage=preview.platformImage
                    }
                    activity=nil
                    prepare()
                    return
                }
                prepared=image;preparedSettings=snapshot;preparedFrameID=selection;preparedImage=preview.platformImage
                status=L("%@ × %@ tiles · %@ candidates per tile", String(describing: image.width), String(describing: image.height), String(describing: tileData.allTiles.count));activity=nil
                let action=nextFrameAction;nextFrameAction = .none
                if action == .weave { solve() }
                if action == .extract { extractPalette() }
            } catch is CancellationError {} catch { if !Task.isCancelled { fail(error) } }
        }
    }
    func extractPalette() {
        if isPlayingVideo,let playback=videoPlayback {
            selectVideoFrame(at:playback.pause(notify:false),after:.extract);return
        }
        guard let image=prepared,!busy else { return }
        activity = .extractingPalette;status=L("Finding strand and background colors…");let count=paletteCount,separation=paletteSeparation.minimumDistance
        guard !selectingVideoFrame else { activity=nil;return }
        let includeAccents=paletteIncludeAccents,input=pictureInput,snapshot=settings,current=preparedIsCurrent
        task=Task {
            do {
                let extracted=try await Task.detached {
                    // A click immediately after an adjustment must use the latest
                    // crop/contrast/grayscale, even before its debounced preview.
                    var target=image
                    if !current,let input { target=try input.prepare(settings:snapshot) }
                    if snapshot.grayscale { target.pixels=target.pixels.map(BackgroundExtractor.neutral) }
                    let palette:[RGB]
                    if includeAccents {
                        var detailed=try input.map { try $0.preparePalette(settings:snapshot) } ?? target
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
                activity=nil;status=L("Extracted %@ of up to %@ strand colors and fitted the background. Edit the colors below.", String(describing: extracted.palette.count), String(describing: count))
                settingsChanged()
            } catch is CancellationError {
                activity=nil;status=L("Color extraction cancelled. Previous colors retained.")
            } catch { fail(error) }
        }
    }
    func solve() {
        guard activeToneSliders.isEmpty else { return }
        if videoSource != nil,!busy,!preparedIsCurrent,let playback=videoPlayback {
            selectVideoFrame(at:playback.pause(notify:false),after:.weave);return
        }
        guard !busy,preparedIsCurrent,let image=prepared else { return }
        let snapshot=settings,name=sourceName
        activity = .exclusive;progress=0;selectedTab=2;status=L("Starting solver…")
        previewTask?.cancel()
        let execution=beginWeaving(title:L("Weaving image"))
        task=Task {
            var succeeded=false
            defer { finishWeaving(execution,success:succeeded) }
            do {
                let output=try await Task.detached(priority:.userInitiated) {
                    try await PartitionSolver.solve(image:image,settings:snapshot,execution:execution) { p,message in
                        await self.update(p,message)
                    }
                }.valueWithCancellation()
                try Task.checkCancellation()
                let result=output.1,data=output.0
                let woven=BraidProject(sourceName:name,settings:snapshot,sampledImage:image,tileData:data,result:result)
                let rendered=try await Task.detached{try TileRenderer.render(woven)}.value
                try await execution?.waitUntilForeground()
                let generated=try await Task.detached { try CurveGenerator.generate(solution:result.solution,data:data) }.value
                try await execution?.waitUntilForeground()
                let tubes=try await Task.detached { try TubeMesher.build(generated) }.value
                try await execution?.waitUntilForeground()
                cameraState=nil;curves=generated;meshes=tubes;curveGeneration+=1
                sceneSettings=SceneSettings(planeColor:data.background)
                project=woven
                project?.sceneSettings=sceneSettings
                if videoSource != nil { checkedVideoSettings=snapshot;checkedFrameTime=videoFrameTime }
                resultImage=rendered.platformImage;zoom=1;activity=nil;progress=1
                let quality=result.allPartitionsOptimal ? L("Every part proven optimal") : L("Feasible result · some parts reached the time or gap limit")
                status=L("%@ · %@ s", String(describing: quality), String(describing: String(format:"%.1f",result.elapsedSeconds)))
                succeeded=true
            } catch is CancellationError { activity=nil;status=L("Cancelled. Previous result retained.") }
            catch { fail(error) }
        }
    }
    private func update(_ p: Double,_ message: String) {
        progress=p;weavingMessage=message
        if weavingState == nil { status=message } else { refreshWeavingStatus() }
    }
    private func beginWeaving(title:String)->PartitionExecutionControl? {
        weavingMessage=status
        #if os(iOS)
        return weavingLifecycle.start(title:title) { [weak self] in self?.cancel() }
        #else
        return nil
        #endif
    }
    private func finishWeaving(_ execution:PartitionExecutionControl?,success:Bool) {
        #if os(iOS)
        if let execution { weavingLifecycle.finish(execution,success:success) }
        #endif
    }
    private func refreshWeavingStatus() {
        // Ending a job must retain its final success/cancellation/error message.
        guard let state=weavingState else { return }
        let message=state.isPaused ? L("Paused until you return to BraidArt.") : state.isBackground ? L("Finishing the current partition before pausing…") : weavingMessage
        if status != message { status=message }
        if let exportProgress,exportProgress.message != message,!exportProgress.cancelling { exportProgress.message=message }
    }
    func cancel() {
        if let exportProgress { exportProgress.cancelling=true;exportProgress.message=L("Cancelling export…") }
        task?.cancel();previewTask?.cancel()
    }
    #if os(macOS)
    func weaveVideo() {
        guard selectedTab==2,canWeaveVideo else { return }
        let panel=NSSavePanel();panel.allowedContentTypes=[.mpeg4Movie];panel.nameFieldStringValue="\(baseName)-braid.mp4"
        panel.message=L("Choose where to save the woven video before processing begins.")
        guard panel.runModal() == .OK,let url=panel.url else { return }
        startVideoExport(to:url)
    }
    #endif
    func startVideoExport(to url:URL) {
        guard canWeaveVideo,let source=videoSource,let segment=videoSegment else { return }
        if let playback=videoPlayback { videoFrameTime=playback.pause(notify:false) }
        let snapshot=settings,format=videoFormat,includeAudio=videoIncludeAudio
        let export=ExportProgress(title:L("Weaving video"),filename:url.lastPathComponent,message:L("Preparing video…"))
        activity = .exclusive;progress=0;status=L("Weaving video…");exportProgress=export
        let execution=beginWeaving(title:L("Weaving video"))
        task=Task {
            var succeeded=false
            defer { finishWeaving(execution,success:succeeded) }
            do {
                let report=try await Task.detached(priority:.userInitiated) {
                    try await VideoWeaver.write(source:source,settings:snapshot,format:format,includeAudio:includeAudio,segment:segment,to:url,execution:execution) { value,message in
                        await MainActor.run {
                            self.update(value,message)
                            if self.weavingState == nil { export.message=message }
                        }
                    }
                }.valueWithCancellation()
                exportProgress=nil;activity=nil;progress=1
                status=L("Saved %@ · %@ frames",url.lastPathComponent,String(report.frames))
                succeeded=true
                #if os(iOS)
                finishMobileExport(url)
                #endif
            } catch is CancellationError {
                #if os(iOS)
                discardMobileExport()
                #endif
                exportProgress=nil;activity=nil;progress=0;status=L("Video weaving cancelled. No incomplete video was saved.")
            } catch { exportProgress=nil;fail(error) }
        }
    }
    private func fail(_ err: Error) {
        #if os(iOS)
        if exportedFile == nil { discardMobileExport() }
        #endif
        activity=nil;error=err.localizedDescription;status=L("Could not complete the operation.")
    }
    #if os(macOS)
    func saveProject() {
        guard let project=projectForSaving,!busy else { return }
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName).braidart";panel.allowedContentTypes=[.braidArtProject];panel.isExtensionHidden=false
        if panel.runModal() == .OK,let url=panel.url {
            do { try project.save(to:url);status=L("Saved %@", String(describing: url.lastPathComponent)) } catch { fail(error) }
        }
    }
    #endif
    var projectForSaving:BraidProject? {
        guard var saved=project else { return nil }
        // This is an extraction preference, so saving it does not replace the
        // colors or geometry associated with the existing woven result.
        saved.settings.backgroundMinimumDistance=settings.backgroundMinimumDistance
        saved.nextOutputSize=settings.outputSize == saved.settings.outputSize ? nil : settings.outputSize
        saved.sceneSettings=sceneSettings;saved.cameraState=cameraState;saved.pictureExportSize=selectedPictureSize
        return saved
    }
    private func loadProject(_ url: URL) {
        activity = .exclusive;status=L("Opening project…")
        task=Task {
            do {
                let loaded=try await Task.detached { try BraidProject.load(from:url) }.value
                let rendered=try await Task.detached{try TileRenderer.render(loaded)}.value
                let generated=try await Task.detached { try CurveGenerator.generate(solution:loaded.result.solution,data:loaded.tileData) }.value
                let tubes=try await Task.detached { try TubeMesher.build(generated) }.value
                curves=generated;meshes=tubes;curveGeneration+=1
                sceneSettings=loaded.sceneSettings ?? SceneSettings(planeColor:loaded.tileData.background)
                cameraState=loaded.cameraState
                selectedPictureSize=loaded.pictureExportSize == .viewport ? nil : loaded.pictureExportSize
                paletteIDs=loaded.settings.palette.map { _ in UUID() }
                clearVideoSource();sourceURL=nil;sourceImage=nil;sourceName=loaded.sourceName;settings=loaded.settings
                if let nextSize=loaded.nextOutputSize { settings.outputSize=nextSize }
                hasCropSelection=loaded.settings.crop != Crop()
                prepared=loaded.sampledImage;preparedSettings=loaded.settings;preparedImage=try ImageProcessor.cgImage(loaded.sampledImage).platformImage
                project=loaded;resultImage=rendered.platformImage;refreshTiles();selectedTab=loaded.cameraState == nil ? 2 : 3;activity=nil
                status=L("Project restored · %@ × %@ tiles", String(describing: loaded.sampledImage.width), String(describing: loaded.sampledImage.height))
            } catch { fail(error) }
        }
    }
    #if os(macOS)
    func exportPNG() {
        guard let project=project,!busy else { return }
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName)-braid.png";panel.allowedContentTypes=[.png]
        guard panel.runModal() == .OK,let url=panel.url else { return }
        activity = .exclusive;status=L("Exporting PNG…")
        task=Task {
            do {
                try await Task.detached { try ImageProcessor.writePNG(TileRenderer.render(project),to:url) }.value
                activity=nil;status=L("Saved %@", String(describing: url.lastPathComponent))
            } catch { fail(error) }
        }
    }
    #endif
    #if os(macOS)
    func exportData() {
        guard let project=projectForSaving,!busy else { return }
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.canCreateDirectories=true
        panel.message=L("Choose a parent folder for the solution, tile data and Wolfram export.")
        guard panel.runModal() == .OK,let parent=panel.url else { return }
        var folder=parent.appendingPathComponent("\(baseName)-braid-data",isDirectory:true);var n=2
        while FileManager.default.fileExists(atPath:folder.path) { folder=parent.appendingPathComponent("\(baseName)-braid-data-\(n)",isDirectory:true);n+=1 }
        let destination=folder;activity = .exclusive;status=L("Exporting solution and tiles…")
        task=Task {
            do {
                try await Task.detached { try ProjectExporter.export(project,to:destination) }.value
                activity=nil;status=L("Exported %@", String(describing: destination.lastPathComponent));NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { fail(error) }
        }
    }
    #endif
    func sceneSettingsChanged() { project?.sceneSettings=sceneSettings }
    func resetCamera() {
        cameraState=nil
        cameraReset+=1
    }
    func cameraChanged(_ state:CameraState) { cameraState=state }
    func register3DView(_ view:BraidMetalView) { threeDView=view }
    #if os(macOS)
    func export3DPicture() {
        guard !busy,exportSavePanel == nil,selectedTab==3,curves != nil,let view=threeDView,let window=view.window else { return }
        let capture:BraidPictureCapture
        let size=pictureExportSize.pixelSize(viewport:.zero)
        do { capture=try view.makePictureCapture(size:size) }
        catch { fail(error);return }
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName)-3d.png";panel.allowedContentTypes=[.png]
        panel.message=L("%@ × %@ pixels · PNG",String(Int(size.width)),String(Int(size.height)))
        exportSavePanel=panel
        panel.beginSheetModal(for:window) { [weak self] response in
            guard let self else { return }
            self.exportSavePanel=nil
            guard response == .OK,let url=panel.url,!self.busy else { return }
            self.startPictureExport(capture,to:url)
        }
    }
    #endif
    private func startPictureExport(_ capture:BraidPictureCapture,to url:URL) {
        let export=ExportProgress(title:L("Exporting 3D Picture"),filename:url.lastPathComponent,message:L("Rendering 3D picture…"))
        activity = .exclusive;progress=0;status=L("Exporting 3D picture…");exportProgress=export
        task=Task {
            do {
                try await Task.detached(priority:.userInitiated) {
                    let image=try capture.render()
                    try Task.checkCancellation()
                    DispatchQueue.main.async {
                        guard !export.cancelling else { return }
                        export.progress=0.8;export.message=L("Saving PNG…")
                    }
                    // Encode beside the destination, then commit only the complete image.
                    let temporary=url.deletingLastPathComponent().appendingPathComponent(".braidart-\(UUID().uuidString).png")
                    defer { try? FileManager.default.removeItem(at:temporary) }
                    try ImageProcessor.writePNG(image,to:temporary)
                    try Task.checkCancellation()
                    try Data(contentsOf:temporary).write(to:url,options:.atomic)
                }.valueWithCancellation()
                exportProgress=nil;activity=nil;progress=1;status=L("Saved %@", String(describing: url.lastPathComponent))
                #if os(iOS)
                finishMobileExport(url)
                #endif
            } catch is CancellationError {
                #if os(iOS)
                discardMobileExport()
                #endif
                exportProgress=nil;activity=nil;progress=0;status=L("Picture export cancelled.")
            } catch {
                exportProgress=nil;fail(error)
            }
        }
    }
    #if os(macOS)
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
    #endif
    private func startPDFExport(_ curves:BraidCurves,to url:URL) {
        let export=ExportProgress(title:L("Exporting PDF"),filename:url.lastPathComponent,message:L("Preparing vector PDF…"))
        activity = .exclusive;progress=0;status=L("Exporting vector PDF…");exportProgress=export
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
                exportProgress=nil;activity=nil;progress=1;status=L("Saved %@", String(describing: url.lastPathComponent))
                #if os(iOS)
                finishMobileExport(url)
                #endif
            } catch is CancellationError {
                #if os(iOS)
                discardMobileExport()
                #endif
                exportProgress=nil;activity=nil;progress=0;status=L("PDF export cancelled.")
            } catch {
                exportProgress=nil;fail(error)
            }
        }
    }
    #if os(macOS)
    func exportGLB() {
        guard let curves,!busy else { return }
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName)-braid.glb";panel.allowedContentTypes=[UTType(filenameExtension:"glb") ?? .data]
        guard panel.runModal() == .OK,let url=panel.url else { return }
        let all=meshes+[TubeMesher.plane(curves,settings:sceneSettings)]
        runExport(L("Exporting colored 3D object…"),success:L("Saved %@", String(describing: url.lastPathComponent))) { try GLBExporter.write(meshes:all,to:url) }
    }
    #endif
    #if os(macOS)
    func exportUSDZ() {
        guard let curves,!busy,exportSavePanel == nil else { return }
        let all=meshes+[TubeMesher.plane(curves,settings:sceneSettings)]
        let panel=NSSavePanel();panel.nameFieldStringValue="\(baseName)-braid.usdz"
        panel.allowedContentTypes=[UTType(filenameExtension:"usdz") ?? .data]
        panel.message=L("Export a colored 3D object for Apple Motion.")
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
    #endif
    private func startUSDZExport(_ meshes:[TubeMesh],to url:URL) {
        let export=ExportProgress(title:L("Exporting USDZ"),filename:url.lastPathComponent,message:L("Preparing USDZ geometry…"))
        activity = .exclusive;progress=0;status=L("Exporting USDZ 3D object…");exportProgress=export
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
                exportProgress=nil;activity=nil;progress=1;status=L("Saved %@", String(describing: url.lastPathComponent))
                #if os(iOS)
                finishMobileExport(url)
                #endif
            } catch is CancellationError {
                #if os(iOS)
                discardMobileExport()
                #endif
                exportProgress=nil;activity=nil;progress=0;status=L("USDZ export cancelled.")
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

#if os(iOS)
extension AppModel {
    func chooseImage() { showingImportChoice=true }
    func openNextSharedMedia(from inbox: SharedMediaInbox) {
        guard !busy else { return }
        do {
            guard let url = try inbox.takeNext(), beginOpeningSource() else { return }
            let file = ImportedPhoto(owning: url)
            if VideoSource.isVideo(url) { openVideo(url, ownedFile: file) }
            else { openImage { (url, file) } }
        } catch { fail(error) }
    }

    func importMobileFile(_ url:URL) {
        guard !busy else { return }
        let access=url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent("BraidImport-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let copy=folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at:url,to:copy)
            open(url:copy)
        } catch { fail(error) }
    }
    private func requestMobileExport(_ name: String, operation: (URL) throws -> Void) {
        guard !busy, mobileExportDirectory == nil else { return }
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BraidExport-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            mobileExportDirectory = folder
            try operation(folder.appendingPathComponent(name))
        } catch { fail(error) }
    }

    private func finishMobileExport(_ url:URL) {
        exportedFile = MobileExportFile(url: url)
    }

    private func discardMobileExport() {
        if let folder = mobileExportDirectory { try? FileManager.default.removeItem(at: folder) }
        mobileExportDirectory = nil
    }

    func finishFileExport(_ file: MobileExportFile, completed: Bool, error: Error?) {
        guard exportedFile?.id == file.id else { return }
        exportedFile = nil
        discardMobileExport()
        if let error { fail(error) }
        else { status = completed ? L("Shared.") : L("Export cancelled.") }
    }
    func saveProject() {
        guard let project=projectForSaving else { return }
        requestMobileExport("\(baseName).braidart") { url in
            try project.save(to:url);self.finishMobileExport(url)
        }
    }
    func exportPNG() {
        guard let project else { return }
        requestMobileExport("\(baseName)-braid.png") { url in
            self.mobileRunExport(url) {
                try ImageProcessor.writePNG(TileRenderer.render(project),to:url)
            }
        }
    }
    func weaveVideo() {
        guard canWeaveVideo else { return }
        requestMobileExport("\(baseName)-braid.mp4") { self.startVideoExport(to:$0) }
    }
    func export3DPicture() {
        guard !busy,selectedTab==3,let view=threeDView else { return }
        do {
            let capture=try view.makePictureCapture(size:pictureExportSize.pixelSize(viewport:.zero))
            requestMobileExport("\(baseName)-3d.png") { self.startPictureExport(capture,to:$0) }
        } catch { fail(error) }
    }
    func exportPDF() {
        guard let curves else { return }
        requestMobileExport("\(baseName)-braid.pdf") { self.startPDFExport(curves,to:$0) }
    }
    func exportGLB() {
        guard let curves else { return }
        let all=meshes+[TubeMesher.plane(curves,settings:sceneSettings)]
        requestMobileExport("\(baseName)-braid.glb") { url in self.mobileRunExport(url) { try GLBExporter.write(meshes:all,to:url) } }
    }
    func exportUSDZ() {
        guard let curves else { return }
        let all=meshes+[TubeMesher.plane(curves,settings:sceneSettings)]
        requestMobileExport("\(baseName)-braid.usdz") { self.startUSDZExport(all,to:$0) }
    }
    func exportData() {
        guard let project=projectForSaving else { return }
        requestMobileExport("\(baseName)-braid-data.zip") { url in
            self.mobileRunExport(url) {
                let directory = url.deletingPathExtension()
                try ProjectExporter.export(project, to: directory)
                try Task.checkCancellation()
                try archiveMobileExport(directory, to: url)
            }
        }
    }
    private func mobileRunExport(_ url:URL,operation:@escaping @Sendable()throws->Void) {
        activity = .exclusive;status=L("Exporting…")
        task=Task {
            do {
                try await Task.detached(priority:.userInitiated) { try operation() }.valueWithCancellation()
                activity=nil;finishMobileExport(url)
            } catch is CancellationError {
                discardMobileExport();activity=nil;status=L("Export cancelled.")
            } catch { fail(error) }
        }
    }
}
#endif
