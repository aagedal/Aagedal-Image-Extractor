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

        let root = outputDirectory.appendingPathComponent("image").path

        var arguments = ["-p"]

        switch format {
        case .jpeg:
            // -j passes through JPEG-encoded images, -png extracts others as PNG
            arguments += ["-j", "-png"]
        case .tiff:
            arguments += ["-tiff"]
        case .jpegXL:
            // Extract as PNG first, then convert to JXL
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
            at: outputDirectory,
            includingPropertiesForKeys: nil
        )

        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "ppm", "pbm", "ccitt"]
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
                let newURL = file.deletingLastPathComponent().appendingPathComponent(newName)
                try fm.moveItem(at: file, to: newURL)
                renamed.append(newURL)
            } else {
                renamed.append(file)
            }
        }

        return renamed
    }
}
