import Foundation

enum ExiftoolLocator {
    private static let homebrewPaths = [
        "/opt/homebrew/bin/exiftool",
        "/usr/local/bin/exiftool",
        "/opt/local/bin/exiftool",
    ]

    static func bundledURL() -> URL? {
        let path = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/exiftool/exiftool")
            .path
        return FileManager.default.isExecutableFile(atPath: path)
            ? URL(fileURLWithPath: path) : nil
    }

    static func homebrewURL() -> URL? {
        let fm = FileManager.default
        for path in homebrewPaths {
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    static func locate(preferBundled: Bool = true) -> URL? {
        if preferBundled {
            return bundledURL() ?? homebrewURL()
        } else {
            return homebrewURL() ?? bundledURL()
        }
    }
}
