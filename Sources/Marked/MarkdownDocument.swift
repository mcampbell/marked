import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
    static let readableContentTypes = [UTType(importedAs: "net.daringfireball.markdown")]

    /// FileWatcher does every read (design), so the document holds no content.
    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}
