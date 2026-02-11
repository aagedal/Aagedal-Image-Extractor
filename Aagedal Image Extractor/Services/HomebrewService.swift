import Foundation

enum HomebrewService {
    private static let brewPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    static func locateBrew() -> URL? {
        let fm = FileManager.default
        for path in brewPaths {
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    static var isInstalled: Bool {
        locateBrew() != nil
    }

    static let installCommand =
        "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

    static func installPoppler() async throws -> ProcessResult {
        guard let brewURL = locateBrew() else {
            throw InstallError.homebrewNotFound
        }
        return try await runProcess(
            executableURL: brewURL,
            arguments: ["install", "poppler"]
        )
    }

    enum InstallError: LocalizedError {
        case homebrewNotFound

        var errorDescription: String? {
            switch self {
            case .homebrewNotFound:
                "Homebrew is not installed. Complete step 1 first."
            }
        }
    }
}
