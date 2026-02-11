import Foundation

struct PDFImageExtractor {
    let pdfimagesURL: URL

    func extract(
        pdfURL: URL,
        to outputDirectory: URL,
        format: ExportFormat
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

        return extracted
    }
}
