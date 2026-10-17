import Foundation

enum ExportFormat: String, CaseIterable {
    case jpeg
    case tiff
    case png
    case jpegXL

    /// Cases currently exposed in the UI (JPEG XL temporarily hidden).
    static let availableCases: [ExportFormat] = [.jpeg, .tiff, .png]

    var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .tiff: "TIFF"
        case .png: "PNG"
        case .jpegXL: "JPEG XL"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .tiff: "tiff"
        case .png: "png"
        case .jpegXL: "jxl"
        }
    }

    func matches(fileExtension: String) -> Bool {
        let ext = fileExtension.lowercased()
        switch self {
        case .jpeg: return ext == "jpg" || ext == "jpeg"
        case .tiff: return ext == "tiff" || ext == "tif"
        case .png: return ext == "png"
        case .jpegXL: return ext == "jxl"
        }
    }
}
