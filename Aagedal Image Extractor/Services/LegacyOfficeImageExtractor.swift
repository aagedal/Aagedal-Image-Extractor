import Foundation

struct LegacyOfficeImageExtractor {
    /// Optional dependency: keep the application lightweight for modern document formats.
    static func locateLibreOffice() -> URL? {
        let paths = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/LibreOffice.app/Contents/MacOS/soffice").path,
            "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice",
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    func extract(documentURL: URL, to outputDirectory: URL, documentName: String,
                 libreOfficeURL: URL? = nil) async throws -> [URL] {
        guard let tool = libreOfficeURL ?? Self.locateLibreOffice() else { throw AppError.libreOfficeNotFound }
        let target: String
        switch DocumentType(url: documentURL) {
        case .doc: target = "docx"
        case .ppt: target = "pptx"
        case .xls: target = "xlsx"
        default: throw AppError.conversionFailed("Unsupported legacy Office format")
        }
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        // A private profile prevents forwarding the conversion to an open LibreOffice window.
        let profile = temporary.appendingPathComponent("profile", isDirectory: true)
        let result = try await runProcess(executableURL: tool, arguments: [
            "-env:UserInstallation=\(profile.absoluteString)", "--headless", "--nologo", "--nodefault",
            "--convert-to", target, "--outdir", temporary.path, documentURL.path,
        ])
        let converted = temporary.appendingPathComponent(documentURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(target)
        guard result.exitCode == 0, fm.fileExists(atPath: converted.path) else {
            throw AppError.conversionFailed("LibreOffice could not convert \(documentURL.lastPathComponent). "
                + "Encrypted or damaged documents are not supported. " + result.stderr + result.stdout)
        }
        return try await ArchiveImageExtractor().extract(documentURL: converted, to: outputDirectory, documentName: documentName)
    }
}
