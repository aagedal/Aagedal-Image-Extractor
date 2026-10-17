import Foundation
import UniformTypeIdentifiers

enum DocumentType: String, CaseIterable {
    case pdf
    case docx, docm, dotx, dotm
    case pptx, pptm, potx, potm, ppsx, ppsm
    case xlsx, xlsm, xltx, xltm
    case odt, odp, ods, ott, otp, ots
    case epub, zip, cbz
    case rtf, rtfd
    case doc, ppt, xls

    init?(url: URL) {
        self.init(rawValue: url.pathExtension.lowercased())
    }

    static var allowedContentTypes: [UTType] {
        allCases.compactMap { UTType(filenameExtension: $0.rawValue) }
    }

    /// Only extract embedded media, excluding previews, attachments and macros.
    var mediaDirectory: String? {
        switch self {
        case .docx, .docm, .dotx, .dotm: "word/media"
        case .pptx, .pptm, .potx, .potm, .ppsx, .ppsm: "ppt/media"
        case .xlsx, .xlsm, .xltx, .xltm: "xl/media"
        case .odt, .odp, .ods, .ott, .otp, .ots: "Pictures"
        default: nil
        }
    }

    var icon: String {
        switch self {
        case .pdf: "doc.richtext"
        case .pptx, .pptm, .potx, .potm, .ppsx, .ppsm, .odp, .otp, .ppt: "rectangle.on.rectangle"
        case .xlsx, .xlsm, .xltx, .xltm, .ods, .ots, .xls: "tablecells"
        case .zip, .cbz: "doc.zipper"
        case .epub: "book"
        default: "doc.text"
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
