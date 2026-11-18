import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let state = ShareImportState()
    private var load: Progress?
    private var cancelled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        let content = UIHostingController(rootView: ShareImportView(state: state, cancel: { [weak self] in
            self?.cancel()
        }, done: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }))
        preferredContentSize = CGSize(width: 400, height: 250)
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)
        NSLayoutConstraint.activate([
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        content.didMove(toParent: self)
        loadAttachment()
    }

    private func loadAttachment() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first,
              let type = provider.registeredTypeIdentifiers.compactMap({ UTType($0) }).first(where: Self.isMedia) else {
            state.phase = .failed
            return
        }
        let suggestedName = provider.suggestedName
        load = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] source, error in
            let result = Result {
                guard let source else { throw error ?? CocoaError(.fileReadUnknown) }
                let filename = Self.filename(for: source, suggestedName: suggestedName, type: type)
                let inbox = try SharedMediaInbox()
                return (inbox, try inbox.stage(source, filename: filename))
            }
            DispatchQueue.main.async {
                guard let self, !self.cancelled else {
                    if case .success((_, let staged)) = result { try? FileManager.default.removeItem(at: staged) }
                    return
                }
                self.load = nil
                do {
                    let (inbox, staged) = try result.get()
                    defer { try? FileManager.default.removeItem(at: staged) }
                    try inbox.enqueue(staged)
                    self.state.phase = .ready
                } catch {
                    self.state.phase = .failed
                }
            }
        }
    }

    nonisolated private static func isMedia(_ type: UTType) -> Bool {
        type.conforms(to: .image) || type.conforms(to: .movie) || type.conforms(to: .video)
    }

    nonisolated private static func filename(for source: URL, suggestedName: String?, type: UTType) -> String {
        let name = (suggestedName as NSString?)?.lastPathComponent ?? source.lastPathComponent
        var base = (name as NSString).deletingPathExtension
        if base.isEmpty || base == "." || base == ".." { base = "BraidArt" }
        if let sourceType = UTType(filenameExtension: source.pathExtension), isMedia(sourceType) {
            return "\(base).\(source.pathExtension)"
        }
        if let suffix = type.preferredFilenameExtension { return "\(base).\(suffix)" }
        return base
    }

    private func cancel() {
        cancelled = true
        load?.cancel()
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}

private final class ShareImportState: ObservableObject {
    enum Phase { case loading, ready, failed }
    @Published var phase: Phase = .loading
}

private struct ShareImportView: View {
    @ObservedObject var state: ShareImportState
    let cancel: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("BraidArt").font(.headline)
            switch state.phase {
            case .loading:
                ProgressView("Importing…")
                Button("Cancel", role: .cancel, action: cancel)
            case .ready:
                Text("Open BraidArt to edit your photo or video.")
                Button("Done", action: done).buttonStyle(.borderedProminent)
            case .failed:
                Text("BraidArt couldn’t import this photo or video.")
                Button("Done", action: done).buttonStyle(.borderedProminent)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
