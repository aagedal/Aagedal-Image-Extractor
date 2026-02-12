import Foundation

struct DOCXImageExtractor {
    func extract(
        docxURL: URL,
        to outputDirectory: URL,
        documentName: String
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
        let sorted = mediaContents
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for (index, file) in sorted.enumerated() {
            let ext = file.pathExtension.lowercased()
            let newName = String(format: "%@_I%03d.%@", documentName, index + 1, ext)
            let destURL = outputDirectory.appendingPathComponent(newName)
            try fm.copyItem(at: file, to: destURL)
            extractedURLs.append(destURL)
        }

        return extractedURLs
    }
}
