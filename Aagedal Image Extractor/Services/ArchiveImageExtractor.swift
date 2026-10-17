import Foundation

struct ArchiveImageExtractor {
    func extract(
        documentURL: URL,
        to outputDirectory: URL,
        documentName: String
    ) async throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        guard let mediaDirectory = DocumentType(url: documentURL)?.mediaDirectory else {
            throw AppError.invalidArchive("Unsupported document type")
        }

        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let unzipURL = URL(fileURLWithPath: "/usr/bin/unzip")
        let listing = try await runProcess(
            executableURL: unzipURL,
            arguments: ["-Z1", documentURL.path]
        )
        guard listing.exitCode == 0 else {
            throw AppError.invalidArchive(listing.stderr)
        }

        let imageExtensions: Set<String> = [
            "jpg", "jpeg", "png", "tiff", "tif", "gif", "bmp", "emf", "wmf", "svg",
            "heic", "heif", "webp", "avif", "jp2", "jxl",
        ]
        let entries = listing.stdout.components(separatedBy: .newlines).filter { entry in
            guard entry.hasPrefix(mediaDirectory + "/") else { return false }
            let name = String(entry.dropFirst(mediaDirectory.count + 1))
            // Media is stored directly in this directory. Ignore nested paths and traversal.
            return !name.contains("/") && !name.contains("\\")
                && imageExtensions.contains((name as NSString).pathExtension.lowercased())
        }
        guard !entries.isEmpty else { throw AppError.noImagesFound }

        // Extract only images, flatten paths and never overwrite. Batch to stay below ARG_MAX.
        for start in stride(from: 0, to: entries.count, by: 100) {
            let patterns = entries[start..<min(start + 100, entries.count)].map { entry in
                entry.reduce(into: "") { pattern, character in
                    if "\\[]*?".contains(character) { pattern.append("\\") }
                    pattern.append(character)
                }
            }
            let result = try await runProcess(
                executableURL: unzipURL,
                arguments: ["-qq", "-j", "-n", documentURL.path] + patterns + ["-d", tempDir.path]
            )
            guard result.exitCode == 0 else {
                throw AppError.invalidArchive(result.stderr)
            }
        }

        let mediaContents = try fm.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )

        var extractedURLs: [URL] = []
        let sorted = try mediaContents
            .filter {
                let values = try $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values.isRegularFile == true && values.isSymbolicLink != true
                    && imageExtensions.contains($0.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard !sorted.isEmpty else { throw AppError.noImagesFound }

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
