import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import BraidCore

struct MobileExportFile:Identifiable {
    let id=UUID()
    let url:URL
}

/// Import a local copy: photo-provider URLs and security scopes may expire on dismissal.
struct PhotoImporter:UIViewControllerRepresentable {
    let complete:(Result<URL,Error>?)->Void
    func makeUIViewController(context:Context)->PHPickerViewController {
        var config=PHPickerConfiguration(photoLibrary:.shared())
        config.filter = .any(of:[.images,.videos]);config.selectionLimit=1
        let picker=PHPickerViewController(configuration:config);picker.delegate=context.coordinator
        return picker
    }
    func updateUIViewController(_ view:PHPickerViewController,context:Context) {}
    func makeCoordinator()->Coordinator { Coordinator(complete:complete) }
    final class Coordinator:NSObject,PHPickerViewControllerDelegate {
        let complete:(Result<URL,Error>?)->Void
        init(complete:@escaping(Result<URL,Error>?)->Void) { self.complete=complete }
        func picker(_ picker:PHPickerViewController,didFinishPicking results:[PHPickerResult]) {
            guard let provider=results.first?.itemProvider else { complete(nil);return }
            let type=provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ? UTType.movie.identifier : UTType.image.identifier
            provider.loadFileRepresentation(forTypeIdentifier:type) { url,error in
                let result:Result<URL,Error>
                do {
                    guard let url else { throw error ?? BraidError.invalid(L("Cannot open the selected picture or video.")) }
                    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("BraidImport-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    let copy=folder.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at:url,to:copy);result = .success(copy)
                } catch { result = .failure(error) }
                DispatchQueue.main.async { self.complete(result) }
            }
        }
    }
}

/// Present UIKit's share sheet modally on iPhone and at the export button on iPad.
struct MobileSharePresenter: UIViewControllerRepresentable {
    let file: MobileExportFile?
    let complete: (MobileExportFile, Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.file = file
        controller.complete = complete
        DispatchQueue.main.async { controller.presentShareSheet() }
    }

    final class Controller: UIViewController {
        var file: MobileExportFile?
        var complete: ((MobileExportFile, Bool, Error?) -> Void)?
        private var presentedFile: UUID?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentShareSheet()
        }

        func presentShareSheet() {
            guard let file, presentedFile != file.id, let window = viewIfLoaded?.window,
                  window.windowScene?.activationState == .foregroundActive,
                  let presenter = window.rootViewController, presenter.presentedViewController == nil else { return }
            let saveCopy = SaveExportToFilesActivity(url: file.url)
            let share = UIActivityViewController(activityItems: [file.url], applicationActivities: [saveCopy])
            let type = UTType(filenameExtension: file.url.pathExtension)
            let canSaveToPhotos = type?.conforms(to: .image) == true || type?.conforms(to: .movie) == true
            share.excludedActivityTypes = canSaveToPhotos ? [.assignToContact] : [.assignToContact, .saveToCameraRoll]
            if traitCollection.userInterfaceIdiom == .pad {
                share.modalPresentationStyle = .popover
                let popover = share.popoverPresentationController
                popover?.sourceView = presenter.view
                popover?.sourceRect = CGRect(x: presenter.view.bounds.maxX - 30,
                                            y: presenter.view.safeAreaInsets.top + 38, width: 1, height: 1)
                popover?.permittedArrowDirections = .up
            }
            let complete = self.complete
            share.completionWithItemsHandler = { _, completed, _, error in complete?(file, completed, error) }
            presentedFile = file.id
            presenter.present(share, animated: true)
        }
    }
}

private final class SaveExportToFilesActivity: UIActivity, UIDocumentPickerDelegate {
    private let url: URL

    init(url: URL) {
        self.url = url
        super.init()
    }

    override class var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? { .init("com.christophefav.BraidArt.SaveExportToFiles") }
    override var activityTitle: String? { L("Save Export to Files") }
    override var activityImage: UIImage? { UIImage(systemName: "folder") }

    override func canPerform(withActivityItems items: [Any]) -> Bool {
        items.contains { ($0 as? URL) == url }
    }

    override var activityViewController: UIViewController? {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = self
        return picker
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        activityDidFinish(!urls.isEmpty)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        activityDidFinish(false)
    }
}

func archiveMobileExport(_ folder: URL, to destination: URL) throws {
    var coordinationError: NSError?
    var copy: Result<Void, Error>?
    NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { snapshot in
        copy = Result { try FileManager.default.copyItem(at: snapshot, to: destination) }
    }
    if let coordinationError { throw coordinationError }
    guard let copy else { throw CocoaError(.fileReadUnknown) }
    try copy.get()
}
