import Foundation

enum AppError: LocalizedError {
    case pdfimagesNotFound
    case pdfimagesExecutionFailed(stderr: String)
    case invalidDocx(String)
    case noImagesFound
    case conversionFailed(String)
    case ocrFailed(String)
    case fileAccessDenied(String)
    case outputDirectoryCreationFailed(String)
    case metadataWriteFailed(String)
    case exiftoolNotFound

    var errorDescription: String? {
        switch self {
        case .pdfimagesNotFound:
            "pdfimages not found. Please reinstall the application."
        case .pdfimagesExecutionFailed(let stderr):
            "pdfimages failed: \(stderr)"
        case .invalidDocx(let detail):
            "Invalid DOCX file: \(detail)"
        case .noImagesFound:
            "No images found in the document"
        case .conversionFailed(let detail):
            "Image conversion failed: \(detail)"
        case .ocrFailed(let detail):
            "OCR failed: \(detail)"
        case .fileAccessDenied(let path):
            "Cannot access file: \(path)"
        case .outputDirectoryCreationFailed(let path):
            "Cannot create output directory: \(path)"
        case .metadataWriteFailed(let detail):
            "Metadata write failed: \(detail)"
        case .exiftoolNotFound:
            "exiftool not found. Please reinstall the application."
        }
    }
}
