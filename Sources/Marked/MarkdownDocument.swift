import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
    static let readableContentTypes = [UTType(importedAs: "net.daringfireball.markdown")]

    let data: Data

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}
