import Foundation

enum ExiftoolLocator {
    private static let searchPaths = [
        "/opt/homebrew/bin/exiftool",
        "/usr/local/bin/exiftool",
        "/opt/local/bin/exiftool",
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
