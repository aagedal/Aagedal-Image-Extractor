import Foundation

enum ExportFormat: String, CaseIterable {
    case original
    case jpeg
    case tiff
    case png
    case jpegXL

    static let availableCases: [ExportFormat] = [.original, .jpeg, .tiff, .png, .jpegXL]

    var displayName: String {
        switch self {
        case .original: "Keep original format"
        case .jpeg: "JPEG"
        case .tiff: "TIFF"
        case .png: "PNG"
        case .jpegXL: "JPEG XL"
        }
    }

    var fileExtension: String {
        switch self {
        case .original: ""
        case .jpeg: "jpg"
        case .tiff: "tiff"
        case .png: "png"
        case .jpegXL: "jxl"
        }
    }

    func matches(fileExtension: String) -> Bool {
        let ext = fileExtension.lowercased()
        switch self {
        case .original: return true
        case .jpeg: return ext == "jpg" || ext == "jpeg"
        case .tiff: return ext == "tiff" || ext == "tif"
        case .png: return ext == "png"
        case .jpegXL: return ext == "jxl"
        }
    }
}
