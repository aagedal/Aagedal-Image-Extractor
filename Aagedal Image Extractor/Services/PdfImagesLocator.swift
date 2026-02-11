import Foundation

enum PdfImagesLocator {
    private static let searchPaths = [
        "/opt/homebrew/bin/pdfimages",
        "/usr/local/bin/pdfimages",
        "/opt/local/bin/pdfimages",
    ]

    static func locate() -> URL? {
        let fm = FileManager.default
        for path in searchPaths {
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
