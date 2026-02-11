import Foundation

enum DocumentType {
    case pdf
    case docx

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "pdf": self = .pdf
        case "docx": self = .docx
        default: return nil
        }
    }

    var icon: String {
        switch self {
        case .pdf: "doc.richtext"
        case .docx: "doc.text"
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
