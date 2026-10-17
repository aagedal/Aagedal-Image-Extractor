import AppKit
import Foundation
import JxlCoder
import ImageIO
import UniformTypeIdentifiers

@main
struct RasterExportChecks {
    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 0.25), atX: 0, y: 0)
        bitmap.setColor(.clear, atX: 1, y: 0)
        bitmap.setColor(.blue, atX: 0, y: 1)
        bitmap.setColor(.green, atX: 1, y: 1)
        let input = root.appendingPathComponent("transparent.tiff")
        try bitmap.tiffRepresentation!.write(to: input)
        var lastProgress = 0.0
        let output = try await ImageConverter().convert(files: [input], to: .png, outputDirectory: root) {
            lastProgress = $0
        }
        precondition(output.count == 1 && output[0].pathExtension == "png")
        let data = try Data(contentsOf: output[0])
        precondition(data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
        let decoded = NSBitmapImageRep(data: data)!
        precondition(decoded.pixelsWide == 2 && decoded.pixelsHigh == 2 && decoded.hasAlpha)
        precondition(abs(decoded.colorAt(x: 0, y: 0)!.alphaComponent - 0.25) < 0.02)
        precondition(decoded.colorAt(x: 1, y: 0)!.alphaComponent == 0)
        precondition(!fm.fileExists(atPath: input.path) && lastProgress == 1)
        _ = try await ImageConverter().convert(files: output, to: .png, outputDirectory: root) { _ in }
        let unchanged = try Data(contentsOf: output[0])
        precondition(unchanged == data, "PNG pass-through must preserve bytes")
        let opaque = root.appendingPathComponent("original.svg")
        let sourceBytes = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        try sourceBytes.write(to: opaque)
        let originals = try await ImageConverter().convert(files: [opaque], to: .original, outputDirectory: root) { _ in }
        let originalBytes = try Data(contentsOf: originals[0])
        precondition(originals == [opaque] && originalBytes == sourceBytes, "Original export must bypass raster decoding")
        let jxlInput = root.appendingPathComponent("jxl-source.png")
        try data.write(to: jxlInput)
        // Exercise the relocated bundle, not only the developer's Homebrew installation.
        let cjxl = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CJXL_TEST_PATH"] ?? CjxlLocator.homebrewURL()!.path)
        let converter = ImageConverter(cjxlURL: cjxl)
        let jxl = try await converter.convert(files: [jxlInput], to: .jpegXL, outputDirectory: root) { _ in }
        let decodedJXL = try JXLCoder.decode(data: Data(contentsOf: jxl[0]))
        let jxlBitmap = NSBitmapImageRep(data: decodedJXL.tiffRepresentation!)!
        precondition(jxlBitmap.pixelsWide == 2 && jxlBitmap.pixelsHigh == 2 && jxlBitmap.hasAlpha)
        precondition(jxlBitmap.colorAt(x: 1, y: 0)!.alphaComponent == 0)
        precondition(abs(jxlBitmap.colorAt(x: 0, y: 0)!.alphaComponent - 0.25) < 0.02)

        let jpeg = root.appendingPathComponent("photo.jpeg")
        let jpegDestination = CGImageDestinationCreateWithURL(jpeg as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(jpegDestination, bitmap.cgImage!, [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "JPEG XL round-trip"],
            kCGImageDestinationLossyCompressionQuality: 0.87,
        ] as CFDictionary)
        precondition(CGImageDestinationFinalize(jpegDestination))
        let originalJPEG = try Data(contentsOf: jpeg)
        let recompressed = try await converter.convert(files: [jpeg], to: .jpegXL, outputDirectory: root) { _ in }
        let jpegXLBytes = try Data(contentsOf: recompressed[0])
        let reconstructedJPEG = try JXLCoder.inverse(jxlData: jpegXLBytes)
        precondition(reconstructedJPEG == originalJPEG, "JPEG recompression must reconstruct every byte, including metadata and orientation")
        let restored = try await converter.convert(files: recompressed, to: .jpeg, outputDirectory: root) { _ in }
        let restoredBytes = try Data(contentsOf: restored[0])
        precondition(restoredBytes == originalJPEG, "JXL to JPEG must use reconstruction when available")
        print("Passed: reversible JPEG recompression and byte-exact reconstruction, including metadata and orientation.")

        // A 16-bit wide-gamut TIFF must retain samples, alpha, dimensions and its embedded profile.
        let samples: [UInt16] = [1234, 23456, 60000, 16384, 56789, 3210, 45678, 65535]
        let pixels = samples.withUnsafeBytes { Data($0) }
        let profile = CGColorSpace(name: CGColorSpace.displayP3)!
        let provider = CGDataProvider(data: pixels as CFData)!
        let highDepth = CGImage(width: 2, height: 1, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: 16,
            space: profile, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder16Little),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let tiff = root.appendingPathComponent("wide-gamut.tiff")
        let tiffDestination = CGImageDestinationCreateWithURL(tiff as CFURL, UTType.tiff.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(tiffDestination, highDepth, nil)
        precondition(CGImageDestinationFinalize(tiffDestination))
        let sourceTIFF = try Data(contentsOf: tiff)
        let encodedHighDepth = try await converter.convert(files: [tiff], to: .jpegXL, outputDirectory: root) { _ in }
        let decodedPNG = root.appendingPathComponent("wide-gamut-decoded.png")
        let djxl = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DJXL_TEST_PATH"] ?? CjxlLocator.homebrewURL()!.deletingLastPathComponent().appendingPathComponent("djxl").path)
        let decodeResult = try await runProcess(executableURL: djxl,
            arguments: [encodedHighDepth[0].path, decodedPNG.path])
        precondition(decodeResult.exitCode == 0)
        let decodedData = try Data(contentsOf: decodedPNG)
        let sourceRep = NSBitmapImageRep(data: sourceTIFF)!
        let resultRep = NSBitmapImageRep(data: decodedData)!
        precondition(sourceRep.bitsPerSample == 16 && resultRep.bitsPerSample == 16)
        precondition(resultRep.pixelsWide == 2 && resultRep.pixelsHigh == 1 && resultRep.hasAlpha)
        for x in 0..<2 {
            var before = [UInt](repeating: 0, count: 4)
            var after = [UInt](repeating: 0, count: 4)
            sourceRep.getPixel(&before, atX: x, y: 0)
            resultRep.getPixel(&after, atX: x, y: 0)
            precondition(before == after, "16-bit pixel samples and alpha must survive lossless encoding")
        }
        let sourceICC = sourceRep.cgImage!.colorSpace!.copyICCData()! as Data
        let resultICC = resultRep.cgImage!.colorSpace!.copyICCData()! as Data
        precondition(sourceICC == resultICC, "Embedded Display P3 profile must survive encoding")
        print("Passed: 16-bit TIFF to JPEG XL preserves exact samples, partial alpha and Display P3 ICC profile.")

        let failingTool = root.appendingPathComponent("failing-cjxl")
        try Data("#!/bin/sh\nexit 7\n".utf8).write(to: failingTool)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: failingTool.path)
        let failureSource = root.appendingPathComponent("failure.png")
        try data.write(to: failureSource)
        let previousOutput = root.appendingPathComponent("failure.jxl")
        let previousBytes = Data("previous output".utf8)
        try previousBytes.write(to: previousOutput)
        do {
            _ = try await ImageConverter(cjxlURL: failingTool).convert(files: [failureSource], to: .jpegXL,
                outputDirectory: root) { _ in }
            preconditionFailure("Expected encoder failure")
        } catch AppError.conversionFailed {}
        let preservedInput = try Data(contentsOf: failureSource)
        let preservedOutput = try Data(contentsOf: previousOutput)
        precondition(preservedInput == data && preservedOutput == previousBytes)
        do {
            _ = try await ImageConverter(cjxlURL: nil).convert(files: [failureSource], to: .jpegXL,
                outputDirectory: root) { _ in }
            preconditionFailure("Expected missing-encoder failure")
        } catch AppError.cjxlNotFound {}
        print("Passed: encoder failures and missing dependencies preserve source and previous output.")
        print("Passed: original-format byte preservation and JPEG XL encoding/decoding with transparency.")
        print("Passed: TIFF to PNG encoding, dimensions, partial/full transparency, progress and PNG pass-through.")

        if CommandLine.arguments.count > 1, !CommandLine.arguments[1].isEmpty {
            let exiftool = URL(fileURLWithPath: CommandLine.arguments[1])
            var configuration = MetadataConfiguration()
            configuration.metadataEnabled = true
            configuration.heading = MetadataFieldConfig(enabled: true, customText: "PNG test")
            try await MetadataWriter(exiftoolURL: exiftool).writeMetadata(to: output,
                configuration: configuration, documentFileName: "test.pptx") { _ in }
            let result = try await runProcess(executableURL: exiftool, arguments: [
                "-j", "-G1", "-struct", "-XMP-photoshop:Headline", "-IPTC:Headline", "-XMP-dc:Subject", output[0].path,
            ])
            precondition(result.exitCode == 0)
            let tags = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as! [[String: Any]]
            precondition(tags[0]["XMP-photoshop:Headline"] as? String == "PNG test")
            precondition(tags[0]["IPTC:Headline"] as? String == "PNG test")
            precondition(tags[0]["XMP-dc:Subject"] as? [String] == ["test.pptx"])
            let tagged = NSBitmapImageRep(data: try Data(contentsOf: output[0]))!
            precondition(tagged.colorAt(x: 1, y: 0)!.alphaComponent == 0)
            print("Passed: PNG XMP/IPTC metadata round-trip and transparency after metadata writing.")
        }
    }
}
