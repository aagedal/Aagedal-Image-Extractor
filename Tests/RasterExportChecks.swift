import AppKit
import Foundation

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
