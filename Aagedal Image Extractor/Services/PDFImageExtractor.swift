import Foundation

struct PDFImageExtractor {
    let pdfimagesURL: URL

    func extract(
        pdfURL: URL,
        to outputDirectory: URL,
        format: ExportFormat,
        documentName: String
    ) async throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // Keep each run isolated so existing output never becomes input to a later run.
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        let root = tempDir.appendingPathComponent("image").path

        var arguments = ["-p"]

        switch format {
        case .original:
            arguments += ["-all"]
        case .jpeg, .jpegXL:
            // -j passes through JPEG-encoded images, -png extracts others as PNG
            arguments += ["-j", "-png"]
        case .tiff:
            arguments += ["-tiff"]
        case .png:
            // Explicit PNG export decodes every image to PNG.
            arguments += ["-png"]
        }

        arguments += [pdfURL.path, root]

        let result = try await runProcess(
            executableURL: pdfimagesURL,
            arguments: arguments
        )

        guard result.exitCode == 0 else {
            throw AppError.pdfimagesExecutionFailed(stderr: result.stderr)
        }

        let contents = try fm.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        )

        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "ppm", "pbm", "ccitt", "params", "jp2", "jb2e", "jb2g"]
        let extracted = contents.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        // Rename from pdfimages convention (image-PPP-NNN.ext) to DocumentName_PPPP_INNN.ext
        // pdfimages page numbers are 1-based, image indices are 0-based
        let pattern = #/^image-(\d+)-(\d+)\.(.+)$/#
        var renamed: [URL] = []

        for file in extracted {
            let filename = file.lastPathComponent
            if let match = filename.firstMatch(of: pattern) {
                let page = Int(match.1) ?? 1
                let imageIndex = (Int(match.2) ?? 0) + 1
                let ext = String(match.3)
                let newName = String(
                    format: "%@_P%03d_I%03d.%@",
                    documentName, page, imageIndex, ext
                )
                let newURL = outputDirectory.appendingPathComponent(newName)
                try fm.moveItem(at: file, to: newURL)
                // JBIG2 globals and CCITT parameters accompany an image; they are not images themselves.
                if !["params", "jb2g"].contains(ext.lowercased()) { renamed.append(newURL) }
            }
        }

        return renamed
    }
}
