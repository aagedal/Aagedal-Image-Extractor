import AppKit
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
        for ext in ["txt", "rar", "exe"] {
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

        // Nested archives must preserve equal basenames and ignore non-images and symlinks.
        let collection = root.appendingPathComponent("collection")
        for folder in ["chapter2", "chapter10", "__MACOSX"] {
            try fm.createDirectory(at: collection.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try imageData.write(to: collection.appendingPathComponent("chapter2/page.png"))
        try Data("second".utf8).write(to: collection.appendingPathComponent("chapter10/page.png"))
        try imageData.write(to: collection.appendingPathComponent("__MACOSX/preview.png"))
        try Data("text".utf8).write(to: collection.appendingPathComponent("notes.txt"))
        try fm.createSymbolicLink(at: collection.appendingPathComponent("link.png"),
                                  withDestinationURL: collection.appendingPathComponent("chapter2/page.png"))
        for ext in ["zip", "cbz"] {
            let archive = root.appendingPathComponent("collection.\(ext)")
            let zipped = try await runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
                arguments: ["-q", "-r", "-y", archive.path, "."], currentDirectoryURL: collection)
            try check(zipped.exitCode == 0, "Create nested archive")
            let files = try await ArchiveImageExtractor().extract(documentURL: archive,
                to: root.appendingPathComponent("collection-output-\(ext)"), documentName: "collection")
            let payloads = try files.map { try Data(contentsOf: $0) }
            try check(payloads == [imageData, Data("second".utf8)], "Nested duplicate basenames and natural ordering")
        }
        for path in ["../bad.png", "/bad.png", "a/../../bad.png", "a/./bad.png", "a\\bad.png", "a//bad.png"] {
            try check(!ArchiveImageExtractor.isSafeEntry(path), "Reject unsafe path: \(path)")
        }

        let ebook = root.appendingPathComponent("ebook")
        try fm.createDirectory(at: ebook.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: ebook.appendingPathComponent("BOOK/images"), withIntermediateDirectories: true)
        try Data("<container><rootfiles><rootfile full-path=\"BOOK/package.opf\"/></rootfiles></container>".utf8)
            .write(to: ebook.appendingPathComponent("META-INF/container.xml"))
        let package = """
        <package><manifest>
          <item href="images/picture%20one.png" media-type="image/png" id="image"/>
          <item href="images/picture%20one.png" media-type="image/png" id="duplicate"/>
        </manifest></package>
        """
        try Data(package.utf8).write(to: ebook.appendingPathComponent("BOOK/package.opf"))
        try imageData.write(to: ebook.appendingPathComponent("BOOK/images/picture one.png"))
        try imageData.write(to: ebook.appendingPathComponent("unlisted.png"))
        let epub = root.appendingPathComponent("book.epub")
        _ = try await runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-q", "-r", epub.path, "."], currentDirectoryURL: ebook)
        let illustrations = try await ArchiveImageExtractor().extract(documentURL: epub,
            to: root.appendingPathComponent("epub-output"), documentName: "book")
        try check(illustrations.count == 1, "EPUB manifest selection, URL decoding and deduplication")
        let illustrationData = try Data(contentsOf: illustrations[0])
        try check(illustrationData == imageData, "Preserve EPUB image bytes")

        // Real AppKit RTFD fixture containing an image and a non-image attachment.
        let richText = NSMutableAttributedString(string: "Images: ")
        let attachment = NSTextAttachment()
        let wrapper = FileWrapper(regularFileWithContents: imageData)
        wrapper.preferredFilename = "image.png"
        attachment.fileWrapper = wrapper
        richText.append(NSAttributedString(attachment: attachment))
        let nonImage = NSTextAttachment()
        nonImage.fileWrapper = FileWrapper(regularFileWithContents: Data("not an image".utf8))
        nonImage.fileWrapper?.preferredFilename = "notes.txt"
        richText.append(NSAttributedString(attachment: nonImage))
        let rtfd = root.appendingPathComponent("rich.rtfd")
        let richWrapper = try richText.fileWrapper(from: NSRange(location: 0, length: richText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        try richWrapper.write(to: rtfd, options: .atomic, originalContentsURL: nil)
        let attachments = try RichTextImageExtractor().extract(documentURL: rtfd,
            to: root.appendingPathComponent("rtfd-output"), documentName: "rich")
        try check(attachments.count == 1, "RTFD exports only image attachments")
        let attachmentData = try Data(contentsOf: attachments[0])
        try check(attachmentData == imageData, "RTFD preserves original attachment bytes")
        let pictureRTF = root.appendingPathComponent("picture.rtf")
        let hex = imageData.map { String(format: "%02x", $0) }.joined()
        try Data(("{\\rtf1\\ansi {\\pict\\pngblip\\picw1\\pich1 " + hex + "}}").utf8).write(to: pictureRTF)
        let rtfImages = try RichTextImageExtractor().extract(documentURL: pictureRTF,
            to: root.appendingPathComponent("rtf-output"), documentName: "picture")
        try check(rtfImages.count == 1, "RTF embedded PNG extraction")
        let plainRTF = root.appendingPathComponent("plain.rtf")
        try Data("{\\rtf1 No pictures}".utf8).write(to: plainRTF)
        do {
            _ = try RichTextImageExtractor().extract(documentURL: plainRTF,
                to: root.appendingPathComponent("rtf-empty"), documentName: "plain")
            throw CheckFailure(message: "Expected no images in text-only RTF")
        } catch AppError.noImagesFound {}

        let binaryRTF = Data("{\\rtf1{\\pict\\pngblip\\bin3 ".utf8) + Data([123, 92, 125]) + Data("}}".utf8)
        let binaryImages = try RTFImageParser.images(in: binaryRTF)
        try check(binaryImages.count == 1 && binaryImages[0].0 == Data([123, 92, 125]), "RTF binary data must not affect group nesting")
        let nestedRTF = Data("{\\rtf1{\\pict\\pngblip{\\*\\blipuid deadbeef} 8950}}".utf8)
        let nestedImages = try RTFImageParser.images(in: nestedRTF)
        try check(nestedImages[0].0 == Data([0x89, 0x50]), "Ignore RTF picture metadata groups")
        do {
            _ = try RTFImageParser.images(in: Data("{\\rtf1{\\pict\\pngblip\\bin999 x}}".utf8))
            throw CheckFailure(message: "Expected invalid RTF binary payload failure")
        } catch AppError.conversionFailed {}

        try await LegacyOfficeChecks.run(root: root, png: imageData)

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
        try Data("""
        #!/bin/sh
        [ "$1" = "-p" ] && [ "$2" = "-j" ] && [ "$3" = "-png" ] || exit 8
        for root do :; done
        printf jpeg > "$root-001-000.jpg"
        """.utf8).write(to: tool)
        let jxlSourceFiles = try await PDFImageExtractor(pdfimagesURL: tool).extract(
            pdfURL: root.appendingPathComponent("test.pdf"), to: root.appendingPathComponent("pdf-jxl"),
            format: .jpegXL, documentName: "test")
        try check(jxlSourceFiles.count == 1 && jxlSourceFiles[0].pathExtension == "jpg",
                  "JPEG XL export must preserve embedded PDF JPEGs for reversible recompression")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
        let noFiles = try await PDFImageExtractor(pdfimagesURL: tool).extract(
            pdfURL: root.appendingPathComponent("empty.pdf"), to: pdfOutput, format: .png, documentName: "empty")
        try check(noFiles.isEmpty, "Old output must not turn an empty PDF into a successful extraction")
        try Data("""
        #!/bin/sh
        [ "$2" = "-all" ] || exit 8
        for root do :; done
        printf jpeg > "$root-001-000.jpg"
        printf jbig2 > "$root-002-001.jb2e"
        printf globals > "$root-002-001.jb2g"
        printf ccitt > "$root-003-002.ccitt"
        printf params > "$root-003-002.params"
        """.utf8).write(to: tool)
        let originalOutput = root.appendingPathComponent("pdf-original")
        let originals = try await PDFImageExtractor(pdfimagesURL: tool).extract(
            pdfURL: root.appendingPathComponent("test.pdf"), to: originalOutput, format: .original, documentName: "test")
        try check(originals.count == 3, "Original PDF export counts images without companion files")
        try check(fm.fileExists(atPath: originalOutput.appendingPathComponent("test_P002_I002.jb2g").path), "Preserve JBIG2 globals")
        try check(fm.fileExists(atPath: originalOutput.appendingPathComponent("test_P003_I003.params").path), "Preserve CCITT parameters")
        try check(ExportFormat.original.matches(fileExtension: "anything"), "Original mode skips all conversion")
        try check(ExportFormat.availableCases.contains(.jpegXL), "Expose JPEG XL")
        print("Passed: 29 input types, Office layouts, nested ZIP/CBZ, EPUB manifests, RTF hex/binary pictures, RTFD attachments, native legacy Office records, symlink/path checks, archive failures, original PDF companion files and process isolation.")
    }
}
