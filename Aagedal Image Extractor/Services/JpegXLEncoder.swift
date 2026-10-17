import Foundation
import ImageIO
import UniformTypeIdentifiers

struct JpegXLEncoder {
    let executableURL: URL

    nonisolated func encode(input: URL, output: URL) async throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let data = try Data(contentsOf: input)
        let source: URL
        let jpeg = data.starts(with: [0xff, 0xd8, 0xff])
        let png = data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        if jpeg || png {
            // Stage with a canonical extension: embedded media filenames are not always reliable.
            source = temporary.appendingPathComponent(jpeg ? "source.jpg" : "source.png")
            try data.write(to: source)
        } else {
            source = temporary.appendingPathComponent("source.png")
            try Self.makePNG(data: data, output: source, filename: input.lastPathComponent)
        }
        // Write in staging first. A failed encoder must never replace a previous output.
        let encoded = temporary.appendingPathComponent("encoded.jxl")
        var arguments = [source.path, encoded.path, "--distance=0", "--effort=7",
                         "--num_threads=\(min(8, max(1, ProcessInfo.processInfo.activeProcessorCount)))"]
        if jpeg { arguments.append("--lossless_jpeg=1") }
        let result = try await runProcess(executableURL: executableURL, arguments: arguments)
        guard result.exitCode == 0, let encodedData = try? Data(contentsOf: encoded),
              Self.isJPEGXL(encodedData) else {
            throw AppError.conversionFailed("JPEG XL encoder failed for \(input.lastPathComponent): "
                + result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try encodedData.write(to: output, options: .atomic)
    }

    nonisolated static func isJPEGXL(_ data: Data) -> Bool {
        data.starts(with: [0xff, 0x0a])
            || data.starts(with: [0, 0, 0, 12, 0x4a, 0x58, 0x4c, 0x20, 13, 10, 0x87, 10])
    }

    nonisolated private static func makePNG(data: Data, output: URL, filename: String) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw AppError.conversionFailed("Cannot read image: \(filename)")
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw AppError.conversionFailed("JPEG XL conversion currently requires a single-frame image: \(filename). Use Keep original format for animated or multi-page images.")
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.bitsPerComponent <= 16,
              !image.bitmapInfo.contains(.floatComponents),
              let model = image.colorSpace?.model, model == .rgb || model == .monochrome else {
            throw AppError.conversionFailed("JPEG XL conversion requires an integer RGB or grayscale image up to 16 bits: \(filename). Use Keep original format to preserve this image.")
        }
        // ImageIO copies the decoded image directly; no NSImage drawing, 8-bit RGB buffer,
        // alpha premultiplication or conversion to a device color space is introduced here.
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw AppError.conversionFailed("Cannot prepare JPEG XL input: \(filename)")
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AppError.conversionFailed("Cannot create lossless PNG intermediate for: \(filename)")
        }
    }
}
