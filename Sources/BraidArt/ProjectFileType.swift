import UniformTypeIdentifiers

extension UTType {
    // JSON is an internal encoding detail. Advertising a text type makes Finder
    // and Quick Look render the source instead of showing the document icon.
    // A new type identity avoids inheriting the obsolete JSON conformance from
    // older installed copies that exported org.braidart.project.
    static let braidArtProject=UTType(exportedAs:"org.braidart.document",conformingTo:.data)
}
