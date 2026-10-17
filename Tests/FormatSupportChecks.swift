import Foundation

private struct CheckFailure: Error {
    let message: String
}

@main
struct FormatSupportChecks {
    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure(message: message) }
    }

    static func expectNoImages(_ operation: () async throws -> [URL]) async throws {
        do {
            _ = try await operation()
            throw CheckFailure(message: "Expected noImagesFound")
        } catch AppError.noImagesFound {}
    }

    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aJ1kAAAAASUVORK5CYII=")!
        for type in DocumentType.allCases {
            try check(DocumentType(url: URL(fileURLWithPath: "Test.\(type.rawValue.uppercased())")) == type,
                      "Uppercase extension: \(type)")
            guard let media = type.mediaDirectory else { continue }
            let fixture = root.appendingPathComponent(type.rawValue)
            let mediaURL = fixture.appendingPathComponent(media)
            try fm.createDirectory(at: mediaURL, withIntermediateDirectories: true)
            try imageData.write(to: mediaURL.appendingPathComponent("image2.PNG"))
            try Data("ten".utf8).write(to: mediaURL.appendingPathComponent("image10.png"))
            try Data("brackets".utf8).write(to: mediaURL.appendingPathComponent("image[1].png"))
            try Data("video".utf8).write(to: mediaURL.appendingPathComponent("movie.mp4"))
            try fm.createSymbolicLink(at: mediaURL.appendingPathComponent("linked.png"),
                                      withDestinationURL: mediaURL.appendingPathComponent("image2.PNG"))
            let thumbnail = fixture.appendingPathComponent("docProps")
            try fm.createDirectory(at: thumbnail, withIntermediateDirectories: true)
            try imageData.write(to: thumbnail.appendingPathComponent("thumbnail.png"))
            let archive = root.appendingPathComponent("Fixture.\(type.rawValue)")
            let zipped = try await runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
                                             arguments: ["-q", "-r", "-y", archive.path, "."],
                                             currentDirectoryURL: fixture)
            try check(zipped.exitCode == 0, "Create fixture: \(zipped.stderr)")
            let output = root.appendingPathComponent("output-\(type.rawValue)")
            let extracted = try await ArchiveImageExtractor().extract(
                documentURL: archive, to: output, documentName: "Fixture"
            )
            try check(extracted.count == 3, "Only embedded regular images should be extracted from \(type)")
            let payloads = try extracted.map { try Data(contentsOf: $0) }
            try check(payloads.contains(imageData) && payloads.contains(Data("brackets".utf8)),
                      "Image bytes and bracketed filenames should survive extraction")
            let two = payloads.firstIndex(of: imageData)!
            let ten = payloads.firstIndex(of: Data("ten".utf8))!
            try check(two < ten, "Images should sort in natural numeric order")
        }
        try check(DocumentType.allowedContentTypes.count == DocumentType.allCases.count,
                  "Every input format must be selectable in the importer")
        for ext in ["doc", "ppt", "xls", "zip", "txt"] {
            try check(DocumentType(url: URL(fileURLWithPath: "file.\(ext)")) == nil, "Reject \(ext)")
        }
        try check(ExportFormat.availableCases.contains(.png), "Expose PNG export")
        try check(ExportFormat.png.matches(fileExtension: "PNG"), "PNG matching")
        try check(ExportFormat.jpeg.matches(fileExtension: "jpeg"), "JPEG alias")
        try check(ExportFormat.tiff.matches(fileExtension: "tif"), "TIFF alias")

        let emptyFixture = root.appendingPathComponent("empty")
        try fm.createDirectory(at: emptyFixture, withIntermediateDirectories: true)
        try Data("empty".utf8).write(to: emptyFixture.appendingPathComponent("content.xml"))
        let emptyArchive = root.appendingPathComponent("empty.odt")
        _ = try await runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
                                 arguments: ["-q", emptyArchive.path, "content.xml"], currentDirectoryURL: emptyFixture)
        try await expectNoImages {
            try await ArchiveImageExtractor().extract(documentURL: emptyArchive,
                to: root.appendingPathComponent("empty-output"), documentName: "empty")
        }
        let corruptArchive = root.appendingPathComponent("corrupt.pptx")
        try Data("not a ZIP file".utf8).write(to: corruptArchive)
        do {
            _ = try await ArchiveImageExtractor().extract(documentURL: corruptArchive,
                to: root.appendingPathComponent("corrupt-output"), documentName: "corrupt")
            throw CheckFailure(message: "Expected corrupt archive failure")
        } catch AppError.invalidArchive {}

        let noisy = try await runProcess(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "yes x | head -c 262144; yes y | head -c 262144 >&2; exit 7"])
        try check(noisy.exitCode == 7 && noisy.stdout.utf8.count == 262144 && noisy.stderr.utf8.count == 262144,
                  "Drain both streams beyond pipe capacity and preserve exit code")
        do {
            _ = try await runProcess(executableURL: root.appendingPathComponent("missing"), arguments: [])
            throw CheckFailure(message: "Expected launch failure")
        } catch is CheckFailure { throw CheckFailure(message: "Expected launch failure") }
          catch {}

        // A controlled pdfimages stand-in exercises naming and isolation without Poppler installed.
        let tool = root.appendingPathComponent("pdfimages")
        try Data("""
        #!/bin/sh
        for root do :; done
        printf 'new image' > "$root-001-000.png"
        """.utf8).write(to: tool)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let pdfOutput = root.appendingPathComponent("pdf-output")
        try fm.createDirectory(at: pdfOutput, withIntermediateDirectories: true)
        let existing = pdfOutput.appendingPathComponent("previous.jpg")
        try Data("previous".utf8).write(to: existing)
        let pdfFiles = try await PDFImageExtractor(pdfimagesURL: tool).extract(
            pdfURL: root.appendingPathComponent("test.pdf"), to: pdfOutput, format: .png, documentName: "test")
        try check(pdfFiles.map(\.lastPathComponent) == ["test_P001_I001.png"], "PDF naming and current-run isolation")
        let existingData = try Data(contentsOf: existing)
        try check(existingData == Data("previous".utf8), "Preserve existing images")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
        let noFiles = try await PDFImageExtractor(pdfimagesURL: tool).extract(
            pdfURL: root.appendingPathComponent("empty.pdf"), to: pdfOutput, format: .png, documentName: "empty")
        try check(noFiles.isEmpty, "Old output must not turn an empty PDF into a successful extraction")
        print("Passed: seven input types, six archive layouts, selective extraction, symlink exclusion, natural ordering, corrupt/empty archives, format aliases, large process output, launch errors and PDF output isolation.")
    }
}
