import Foundation

struct ArchiveImageExtractor {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "tif", "gif", "bmp", "emf", "wmf", "svg",
        "heic", "heif", "webp", "avif", "jp2", "jxl", "dib", "pict", "pct",
    ]

    // Reject ambiguous and unsafe names before passing any archive paths to unzip.
    static func isSafeEntry(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
            && !path.contains("\0") && !path.contains("\r")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains {
                $0 == ".." || $0 == "." || $0.isEmpty
            }
    }

    private func literalPattern(_ entry: String) -> String {
        entry.reduce(into: "") { pattern, character in
            if "\\[]*?".contains(character) { pattern.append("\\") }
            pattern.append(character)
        }
    }

    private func readXML(_ entry: String, archive: URL) async throws -> ArchiveXML {
        guard Self.isSafeEntry(entry) else { throw AppError.invalidArchive("Unsafe EPUB resource path") }
        let result = try await runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
                                          arguments: ["-p", archive.path, literalPattern(entry)])
        guard result.exitCode == 0 else { throw AppError.invalidArchive("Missing EPUB resource: \(entry)") }
        let delegate = ArchiveXML()
        let parser = XMLParser(data: Data(result.stdout.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw AppError.invalidArchive("Invalid EPUB XML: \(entry)") }
        return delegate
    }

    private func epubImages(archive: URL, entries: Set<String>) async throws -> Set<String> {
        let container = try await readXML("META-INF/container.xml", archive: archive)
        guard !container.rootfiles.isEmpty else { throw AppError.invalidArchive("EPUB has no package document") }
        var images: Set<String> = []
        for packagePath in container.rootfiles {
            guard entries.contains(packagePath) else { throw AppError.invalidArchive("Missing EPUB package") }
            let package = try await readXML(packagePath, archive: archive)
            // Resolve relative manifest URLs, including percent encoding, without accessing the filesystem or network.
            let root = URL(fileURLWithPath: "/epub-container/", isDirectory: true)
            let base = root.appendingPathComponent(packagePath).deletingLastPathComponent()
            for href in package.images {
                guard let components = URLComponents(string: href), components.scheme == nil,
                      components.host == nil, !href.hasPrefix("/"),
                      let decoded = components.percentEncodedPath.removingPercentEncoding else {
                    throw AppError.invalidArchive("Unsupported EPUB image URL: \(href)")
                }
                let resolved = base.appendingPathComponent(decoded).standardizedFileURL.path
                guard resolved.hasPrefix(root.path + "/") else {
                    throw AppError.invalidArchive("EPUB image path leaves the container")
                }
                let path = String(resolved.dropFirst(root.path.count + 1))
                guard Self.isSafeEntry(path), entries.contains(path) else {
                    throw AppError.invalidArchive("Missing or unsafe EPUB image: \(href)")
                }
                images.insert(path)
            }
        }
        return images
    }

    func extract(documentURL: URL, to outputDirectory: URL, documentName: String) async throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        guard let type = DocumentType(url: documentURL),
              type.mediaDirectory != nil || [.epub, .zip, .cbz].contains(type) else {
            throw AppError.invalidArchive("Unsupported document type")
        }
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let unzipURL = URL(fileURLWithPath: "/usr/bin/unzip")
        let listing = try await runProcess(executableURL: unzipURL, arguments: ["-Z1", documentURL.path])
        guard listing.exitCode == 0 else { throw AppError.invalidArchive(listing.stderr) }
        let allEntries = listing.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasSuffix("/") }
        guard Set(allEntries).count == allEntries.count else {
            throw AppError.invalidArchive("Duplicate archive paths are not supported")
        }
        let manifestImages: Set<String>?
        if type == .epub {
            let images = try await epubImages(archive: documentURL, entries: Set(allEntries))
            if allEntries.contains("META-INF/encryption.xml") {
                let encryption = try await readXML("META-INF/encryption.xml", archive: documentURL)
                let encrypted = Set(encryption.encryptedResources.map { $0.removingPercentEncoding ?? $0 })
                guard images.isDisjoint(with: encrypted) else {
                    throw AppError.invalidArchive("Encrypted EPUB images are not supported")
                }
            }
            manifestImages = images
        } else { manifestImages = nil }
        let entries = allEntries.filter { entry in
            guard Self.isSafeEntry(entry) else { return false }
            if let manifestImages { return manifestImages.contains(entry) }
            guard Self.imageExtensions.contains((entry as NSString).pathExtension.lowercased()) else { return false }
            if let media = type.mediaDirectory {
                guard entry.hasPrefix(media + "/") else { return false }
                return !entry.dropFirst(media.count + 1).contains("/")
            }
            return !entry.split(separator: "/").contains { $0 == "__MACOSX" || $0.hasPrefix(".") }
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        var extracted: [URL] = []
        // Isolate each entry to preserve equal basenames in different folders and exclude symlinks.
        for (index, entry) in entries.enumerated() {
            let staging = tempDir.appendingPathComponent(String(index))
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let result = try await runProcess(executableURL: unzipURL,
                arguments: ["-qq", "-j", "-n", documentURL.path, literalPattern(entry), "-d", staging.path])
            guard result.exitCode == 0 else { throw AppError.invalidArchive(result.stderr) }
            let files = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            for file in files {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                let ext = file.pathExtension.lowercased()
                let name = String(format: "%@_I%03d", documentName, extracted.count + 1)
                    + (ext.isEmpty ? "" : "." + ext)
                let output = outputDirectory.appendingPathComponent(name)
                try fm.copyItem(at: file, to: output)
                extracted.append(output)
            }
        }
        guard !extracted.isEmpty else { throw AppError.noImagesFound }
        return extracted
    }
}

private final class ArchiveXML: NSObject, XMLParserDelegate {
    var rootfiles: [String] = []
    var images: [String] = []
    var encryptedResources: [String] = []
    private var inManifest = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "rootfile", let path = attributes["full-path"] { rootfiles.append(path) }
        if name == "CipherReference", let uri = attributes["URI"] { encryptedResources.append(uri) }
        if name == "manifest" { inManifest = true }
        if inManifest, name == "item", attributes["media-type"]?.hasPrefix("image/") == true,
           let href = attributes["href"] { images.append(href) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.split(separator: ":").last == "manifest" { inManifest = false }
    }
}
