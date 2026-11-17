import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import BraidCore

enum MobileExportDestination { case photos,files }
struct MobileExportRequest:Identifiable {
    let id=UUID()
    let name:String
    let allowsPhotos:Bool
    let start:(MobileExportDestination)->Void
}
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

/// Standard Files save UI, including iCloud Drive and installed file providers.
struct FileExporter:UIViewControllerRepresentable {
    let url:URL
    let complete:(Bool)->Void
    func makeUIViewController(context:Context)->UIDocumentPickerViewController {
        let picker=UIDocumentPickerViewController(forExporting:[url],asCopy:true)
        picker.delegate=context.coordinator
        return picker
    }
    func updateUIViewController(_ view:UIDocumentPickerViewController,context:Context) {}
    func makeCoordinator()->Coordinator { Coordinator(complete:complete) }
    final class Coordinator:NSObject,UIDocumentPickerDelegate {
        let complete:(Bool)->Void
        init(complete:@escaping(Bool)->Void) { self.complete=complete }
        func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) { complete(true) }
        func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) { complete(false) }
    }
}
