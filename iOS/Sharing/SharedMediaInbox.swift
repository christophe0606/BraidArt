import Foundation

struct SharedMediaInbox {
    private static let appGroup = "group.com.christophefav.BraidArt"
    let root: URL

    init() throws {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else {
            throw CocoaError(.fileNoSuchFile)
        }
        self.init(root: container.appendingPathComponent("SharedMedia", isDirectory: true))
    }

    init(root: URL) { self.root = root }

    private var ready: URL { root.appendingPathComponent("Ready", isDirectory: true) }

    func stage(_ source: URL, filename: String) throws -> URL {
        let fm = FileManager.default
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw CocoaError(.fileReadUnknown)
            }
            try fm.copyItem(at: source, to: folder.appendingPathComponent(filename))
            return folder
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }

    func enqueue(_ staged: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: ready, withIntermediateDirectories: true)
        try fm.moveItem(at: staged, to: ready.appendingPathComponent(staged.lastPathComponent))
    }

    func takeNext() throws -> URL? {
        let fm = FileManager.default
        let folders: [URL]
        do {
            folders = try fm.contentsOfDirectory(at: ready, includingPropertiesForKeys: [.creationDateKey])
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        let ordered = folders.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
        }
        for folder in ordered {
            guard let file = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first else {
                try fm.removeItem(at: folder)
                continue
            }
            let local = fm.temporaryDirectory.appendingPathComponent("BraidImport-\(UUID().uuidString)", isDirectory: true)
            try fm.moveItem(at: folder, to: local)
            return local.appendingPathComponent(file.lastPathComponent)
        }
        return nil
    }
}
