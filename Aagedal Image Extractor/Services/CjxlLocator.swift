import Foundation

enum CjxlLocator {
    private static let homebrewPaths = [
        "/opt/homebrew/bin/cjxl",
        "/usr/local/bin/cjxl",
        "/opt/local/bin/cjxl",
    ]

    static func bundledURL() -> URL? {
        let path = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/cjxl")
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
