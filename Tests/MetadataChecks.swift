import AppKit
import Foundation

@main
struct MetadataChecks {
    @MainActor
    static func main() async throws {
        var config = MetadataConfiguration()
        config.metadataEnabled = true
        config.heading = MetadataFieldConfig(enabled: true, includeDocumentName: true,
                                            customText: "  Archive \n", textPlacement: .prepend)
        config.description = MetadataFieldConfig(enabled: true, customText: " \n ")
        config.keywords.customText = " history; photos, , collection \n"
        config.keywords.textPlacement = .append
        let resolved = MetadataWriter.resolve(configuration: config, documentFileName: "Source.pdf", pageNumber: 12)
        precondition(resolved.heading == "Archive Source.pdf")
        precondition(resolved.description == nil, "Blank fields leave existing metadata unchanged")
        precondition(resolved.keywords == ["Source.pdf", "history", "photos", "collection"])
        precondition(resolved.extendedDescription == "File name: Source.pdf, Page: 12")
        precondition(resolved.previewFields.count == 3)
        precondition(MetadataWriter.parsePageNumber(from: "Source_P012_I002.png") == 12)
        precondition(MetadataWriter.parsePageNumber(from: "Source_I002.png") == nil)
        let noPage = MetadataWriter.resolve(configuration: config, documentFileName: "Source.docx", pageNumber: nil)
        precondition(noPage.extendedDescription == "File name: Source.docx")
        config.heading.textPlacement = .append
        config.extendedDescription.includeDocumentName = false
        config.extendedDescription.customText = "Manual description"
        let manual = MetadataWriter.resolve(configuration: config, documentFileName: "Source.pdf", pageNumber: 12)
        precondition(manual.heading == "Source.pdf Archive")
        precondition(manual.extendedDescription == "Manual description")
        config.heading.enabled = false
        precondition(MetadataWriter.resolve(configuration: config, documentFileName: "Source.pdf", pageNumber: 12).heading == nil)
        print("Passed: metadata preview values, blank/disabled fields, text placement, keyword separators and PDF-only page descriptions.")

        guard CommandLine.arguments.count > 1, !CommandLine.arguments[1].isEmpty else {
            print("Skipped: real metadata round trip (install exiftool to enable).")
            return
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                      isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<2 {
            for y in 0..<2 { bitmap.setColor(.red, atX: x, y: y) }
        }
        let image = root.appendingPathComponent("Source_P012_I002.jpg")
        try bitmap.representation(using: .jpeg, properties: [:])!.write(to: image)
        let tool = URL(fileURLWithPath: CommandLine.arguments[1])
        let seeded = try await runProcess(executableURL: tool, arguments: ["-overwrite_original", "-XMP-dc:Description=Keep this", "-IPTC:Keywords=old", "-XMP-dc:Subject=old", image.path])
        precondition(seeded.exitCode == 0, seeded.stderr)
        config.heading.enabled = true
        config.description.customText = "\n "
        let expected = MetadataWriter.resolve(configuration: config, documentFileName: "Source.pdf", pageNumber: 12)
        var progress: [Double] = []
        try await MetadataWriter(exiftoolURL: tool).writeMetadata(to: [image], configuration: config,
                                                                documentFileName: "Source.pdf") { progress.append($0) }
        // Repeating the write must replace both lists without accumulating duplicates.
        try await MetadataWriter(exiftoolURL: tool).writeMetadata(to: [image], configuration: config,
                                                                documentFileName: "Source.pdf") { _ in }
        let read = try await runProcess(executableURL: tool, arguments: ["-j", "-G1", "-XMP:all", "-IPTC:all", image.path])
        let values = (try JSONSerialization.jsonObject(with: Data(read.stdout.utf8)) as! [[String: Any]])[0]
        precondition(values["XMP-photoshop:Headline"] as? String == expected.heading)
        precondition(values["IPTC:Headline"] as? String == expected.heading)
        precondition(values["XMP-dc:Description"] as? String == "Keep this")
        precondition(values["XMP-dc:Subject"] as? [String] == expected.keywords)
        precondition(values["IPTC:Keywords"] as? [String] == expected.keywords, read.stdout)
        precondition(values["XMP-iptcCore:ExtDescrAccessibility"] as? String == expected.extendedDescription)
        precondition(progress == [1])
        precondition(!fm.fileExists(atPath: image.path + "_original"))
        print("Passed: real ExifTool XMP/IPTC round trip matches preview, preserves blank fields, replaces keywords and leaves no backup file.")
    }
}
