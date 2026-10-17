import Foundation
import UniformTypeIdentifiers

enum DocumentType: String, CaseIterable {
    case pdf
    case docx
    case pptx
    case xlsx
    case odt
    case odp
    case ods

    init?(url: URL) {
        self.init(rawValue: url.pathExtension.lowercased())
    }

    static var allowedContentTypes: [UTType] {
        allCases.compactMap { UTType(filenameExtension: $0.rawValue) }
    }

    /// Only extract embedded media, excluding previews, attachments and macros.
    var mediaDirectory: String? {
        switch self {
        case .pdf: nil
        case .docx: "word/media"
        case .pptx: "ppt/media"
        case .xlsx: "xl/media"
        case .odt, .odp, .ods: "Pictures"
        }
    }

    var icon: String {
        switch self {
        case .pdf: "doc.richtext"
        case .docx, .odt: "doc.text"
        case .pptx, .odp: "rectangle.on.rectangle"
        case .xlsx, .ods: "tablecells"
        }
    }
}

@Observable
final class DocumentItem: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let fileName: String
    let documentType: DocumentType
    var state: ProcessingState = .pending
    var extractedImageCount: Int = 0
    var outputDirectoryURL: URL?

    init(sourceURL: URL, documentType: DocumentType) {
        self.sourceURL = sourceURL
        self.fileName = sourceURL.lastPathComponent
        self.documentType = documentType
    }

    var defaultOutputDirectory: URL {
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        return sourceURL.deletingLastPathComponent().appendingPathComponent("\(stem)_images")
    }
}
