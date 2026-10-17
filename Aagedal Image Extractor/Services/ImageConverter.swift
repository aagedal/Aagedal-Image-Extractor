import AppKit
import Foundation
import JxlCoder

struct ImageConverter {
    func convert(
        files: [URL],
        to format: ExportFormat,
        outputDirectory: URL,
        progressHandler: @MainActor (Double) -> Void
    ) async throws -> [URL] {
        var outputURLs: [URL] = []
        let total = Double(files.count)

        for (index, file) in files.enumerated() {
            // Skip if already in target format
            if format.matches(fileExtension: file.pathExtension) {
                outputURLs.append(file)
                progressHandler(Double(index + 1) / total)
                continue
            }

            let newName = file.deletingPathExtension()
                .lastPathComponent + "." + format.fileExtension
            let outputURL = outputDirectory.appendingPathComponent(newName)

            try await convertFile(file, to: outputURL, format: format)
            outputURLs.append(outputURL)

            // Remove original if we created a new file
            try? FileManager.default.removeItem(at: file)

            progressHandler(Double(index + 1) / total)
        }

        return outputURLs
    }

    nonisolated private func convertFile(
        _ input: URL,
        to output: URL,
        format: ExportFormat
    ) async throws {
        let data = try Data(contentsOf: input)
        guard let imageRep = NSBitmapImageRep(data: data) else {
            throw AppError.conversionFailed("Cannot read image: \(input.lastPathComponent)")
        }

        let outputData: Data?

        switch format {
        case .jpeg:
            outputData = imageRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.92]
            )
        case .tiff:
            outputData = imageRep.tiffRepresentation(
                using: .lzw,
                factor: 0
            )
        case .png:
            outputData = imageRep.representation(using: .png, properties: [:])
        case .jpegXL:
            guard let cgImage = imageRep.cgImage else {
                throw AppError.conversionFailed(
                    "Cannot create CGImage from: \(input.lastPathComponent)"
                )
            }
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                width: imageRep.pixelsWide,
                height: imageRep.pixelsHigh
            ))
            outputData = try JXLCoder.encode(image: nsImage)
        }

        guard let finalData = outputData else {
            throw AppError.conversionFailed(
                "Conversion produced no data for: \(input.lastPathComponent)"
            )
        }

        try finalData.write(to: output, options: .atomic)
    }
}
