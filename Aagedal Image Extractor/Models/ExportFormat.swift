import Foundation

enum ExportFormat: String, CaseIterable {
    case jpeg
    case tiff
    case jpegXL

    var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .tiff: "TIFF"
        case .jpegXL: "JPEG XL"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .tiff: "tiff"
        case .jpegXL: "jxl"
        }
    }

    /// Flag for pdfimages. nil means extract as PNG then convert.
    var pdfimagesFlag: String? {
        switch self {
        case .jpeg: "-j"
        case .tiff: "-tiff"
        case .jpegXL: nil
        }
    }
}
