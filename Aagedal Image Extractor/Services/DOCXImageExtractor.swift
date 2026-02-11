import Foundation

struct DOCXImageExtractor {
    func extract(
        docxURL: URL,
        to outputDirectory: URL
    ) async throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: tempDir) }

        let unzipURL = URL(fileURLWithPath: "/usr/bin/unzip")
        let result = try await runProcess(
            executableURL: unzipURL,
            arguments: ["-o", docxURL.path, "-d", tempDir.path]
        )

        guard result.exitCode == 0 else {
            throw AppError.invalidDocx(result.stderr)
        }

        let mediaDir = tempDir.appendingPathComponent("word/media")
        guard fm.fileExists(atPath: mediaDir.path) else {
            throw AppError.noImagesFound
        }

        let mediaContents = try fm.contentsOfDirectory(
            at: mediaDir,
            includingPropertiesForKeys: nil
        )

        let imageExtensions: Set<String> = [
            "jpg", "jpeg", "png", "tiff", "tif", "gif", "bmp", "emf", "wmf", "svg",
        ]

        var extractedURLs: [URL] = []
        for file in mediaContents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard imageExtensions.contains(file.pathExtension.lowercased()) else { continue }
            let destURL = outputDirectory.appendingPathComponent(file.lastPathComponent)
            try fm.copyItem(at: file, to: destURL)
            extractedURLs.append(destURL)
        }

        return extractedURLs
    }
}
