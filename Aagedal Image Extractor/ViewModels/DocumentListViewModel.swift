import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "aagedal.Aagedal-Image-Extractor", category: "Pipeline")

@Observable
final class DocumentListViewModel {
    var documents: [DocumentItem] = []
    var selectedFormat: ExportFormat = .jpeg
    var ocrEnabled: Bool = false
    var metadataConfiguration = MetadataConfiguration()
    var exiftoolURL: URL?
    var cjxlURL: URL?
    var pdfimagesURL: URL?
    var homebrewInstalled: Bool = HomebrewService.isInstalled
    var isInstallingPoppler: Bool = false
    var installError: String?
    var setupDismissed: Bool = false
    var errorMessage: String?
    var showError: Bool = false
    var preferBundledTools: Bool = true
    var outputDestination: OutputDestination = .nextToOriginals
    var customOutputDirectoryURL: URL?

    var cjxlBundledAvailable: Bool { CjxlLocator.bundledURL() != nil }
    var cjxlHomebrewAvailable: Bool { CjxlLocator.homebrewURL() != nil }

    var pdfimagesBundledAvailable: Bool { PdfImagesLocator.bundledURL() != nil }
    var pdfimagesHomebrewAvailable: Bool { PdfImagesLocator.homebrewURL() != nil }
    var exiftoolBundledAvailable: Bool { ExiftoolLocator.bundledURL() != nil }
    var exiftoolHomebrewAvailable: Bool { ExiftoolLocator.homebrewURL() != nil }

    var exiftoolAvailable: Bool { exiftoolURL != nil }
    var pdfimagesAvailable: Bool { pdfimagesURL != nil }
    var hasDocuments: Bool { !documents.isEmpty }
    var hasPendingDocuments: Bool { documents.contains { $0.state == .pending } }
    private(set) var isProcessing: Bool = false

    private static let metadataConfigKey = "MetadataConfiguration"
    private static let exportFormatKey = "ExportFormat"
    private static let preferBundledToolsKey = "PreferBundledTools"
    private static let outputDestinationKey = "OutputDestination"
    private static let customOutputDirectoryBookmarkKey = "CustomOutputDirectoryBookmark"

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.preferBundledToolsKey) != nil {
            preferBundledTools = defaults.bool(forKey: Self.preferBundledToolsKey)
        }
        cjxlURL = CjxlLocator.locate(preferBundled: preferBundledTools)
        pdfimagesURL = PdfImagesLocator.locate(preferBundled: preferBundledTools)
        exiftoolURL = ExiftoolLocator.locate(preferBundled: preferBundledTools)
        if let data = defaults.data(forKey: Self.metadataConfigKey),
           let saved = try? JSONDecoder().decode(MetadataConfiguration.self, from: data) {
            metadataConfiguration = saved
        }
        if let raw = defaults.string(forKey: Self.exportFormatKey),
           let saved = ExportFormat(rawValue: raw), ExportFormat.availableCases.contains(saved) {
            selectedFormat = saved
        }
        if let raw = defaults.string(forKey: Self.outputDestinationKey),
           let saved = OutputDestination(rawValue: raw) {
            outputDestination = saved
        }
        if let bookmarkData = defaults.data(forKey: Self.customOutputDirectoryBookmarkKey) {
            var isStale = false
            customOutputDirectoryURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
    }

    func saveFormatSelection() {
        UserDefaults.standard.set(selectedFormat.rawValue, forKey: Self.exportFormatKey)
    }

    func saveOutputDestination() {
        let defaults = UserDefaults.standard
        defaults.set(outputDestination.rawValue, forKey: Self.outputDestinationKey)
        if let url = customOutputDirectoryURL,
           let bookmarkData = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmarkData, forKey: Self.customOutputDirectoryBookmarkKey)
        }
    }

    func saveMetadataConfiguration() {
        if let data = try? JSONEncoder().encode(metadataConfiguration) {
            UserDefaults.standard.set(data, forKey: Self.metadataConfigKey)
        }
    }

    func addDocuments(urls: [URL]) {
        for url in urls {
            guard let type = DocumentType(url: url) else { continue }
            guard !documents.contains(where: { $0.sourceURL == url }) else { continue }
            documents.append(DocumentItem(sourceURL: url, documentType: type))
        }
    }

    func removeDocument(_ item: DocumentItem) {
        guard !item.state.isProcessing else { return }
        documents.removeAll { $0.id == item.id }
    }

    func clearFinished() {
        documents.removeAll { $0.state.isFinished }
    }

    func revealInFinder(_ item: DocumentItem) {
        if let outputDir = item.outputDirectoryURL {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputDir.path)
        }
    }

    func refreshDependencies() {
        homebrewInstalled = HomebrewService.isInstalled
        cjxlURL = CjxlLocator.locate(preferBundled: preferBundledTools)
        pdfimagesURL = PdfImagesLocator.locate(preferBundled: preferBundledTools)
        exiftoolURL = ExiftoolLocator.locate(preferBundled: preferBundledTools)
        installError = nil
    }

    func saveToolSourcePreference() {
        UserDefaults.standard.set(preferBundledTools, forKey: Self.preferBundledToolsKey)
        refreshDependencies()
    }

    func installPoppler() async {
        isInstallingPoppler = true
        installError = nil
        do {
            let result = try await HomebrewService.installPoppler()
            if result.exitCode == 0 {
                refreshDependencies()
            } else {
                let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                installError = message.isEmpty
                    ? "Installation failed (exit code \(result.exitCode))"
                    : message
            }
        } catch {
            installError = error.localizedDescription
        }
        isInstallingPoppler = false
    }

    // Capture settings once so edits made while awaiting a tool apply to the next batch.
    private struct BatchSettings {
        let format: ExportFormat
        let ocrEnabled: Bool
        let metadata: MetadataConfiguration
        let cjxlURL: URL?
        let pdfimagesURL: URL?
        let exiftoolURL: URL?
        let outputDestination: OutputDestination
        let customOutputDirectoryURL: URL?
    }

    func processAll() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        let settings = BatchSettings(
            format: selectedFormat,
            ocrEnabled: ocrEnabled,
            metadata: metadataConfiguration,
            cjxlURL: cjxlURL,
            pdfimagesURL: pdfimagesURL,
            exiftoolURL: exiftoolURL,
            outputDestination: outputDestination,
            customOutputDirectoryURL: customOutputDirectoryURL
        )
        let pending = documents.filter { $0.state == .pending }
        for item in pending {
            // A queued document may have been removed while the previous one was running.
            guard documents.contains(where: { $0.id == item.id }), item.state == .pending else { continue }
            await processSingle(item, settings: settings)
        }
    }

    private func processSingle(_ item: DocumentItem, settings: BatchSettings) async {
        var outputDir: URL
        switch settings.outputDestination {
        case .nextToOriginals:
            outputDir = item.defaultOutputDirectory
        case .customDirectory:
            guard let baseDir = settings.customOutputDirectoryURL else {
                item.state = .failed(message: "No custom output directory selected")
                return
            }
            let docStem = item.sourceURL.deletingPathExtension().lastPathComponent
            outputDir = baseDir.appendingPathComponent("\(docStem)_images")
        }
        item.state = .extracting(progress: 0)
        logger.info("Starting processing: \(item.fileName)")

        do {
            // Preserve previous exports, including documents with the same stem in a batch.
            let baseOutputDir = outputDir
            var suffix = 2
            while FileManager.default.fileExists(atPath: outputDir.path) {
                outputDir = baseOutputDir.deletingLastPathComponent().appendingPathComponent(
                    baseOutputDir.lastPathComponent + "_\(suffix)"
                )
                suffix += 1
            }
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            item.outputDirectoryURL = outputDir
            var extractedFiles: [URL]

            let docStem = item.sourceURL.deletingPathExtension().lastPathComponent

            switch item.documentType {
            case .pdf:
                guard let pdfimagesURL = settings.pdfimagesURL else {
                    throw AppError.pdfimagesNotFound
                }
                let extractor = PDFImageExtractor(pdfimagesURL: pdfimagesURL)
                extractedFiles = try await extractor.extract(
                    pdfURL: item.sourceURL,
                    to: outputDir,
                    format: settings.format,
                    documentName: docStem
                )
                logger.info("Extracted \(extractedFiles.count) files from PDF")
            case .rtf, .rtfd:
                extractedFiles = try RichTextImageExtractor().extract(
                    documentURL: item.sourceURL, to: outputDir, documentName: docStem)
            case .doc, .ppt, .xls:
                extractedFiles = try await LegacyOfficeImageExtractor().extract(
                    documentURL: item.sourceURL, to: outputDir, documentName: docStem)
            default:
                let extractor = ArchiveImageExtractor()
                extractedFiles = try await extractor.extract(
                    documentURL: item.sourceURL,
                    to: outputDir,
                    documentName: docStem
                )
                logger.info("Extracted \(extractedFiles.count) files from document archive")
            }

            item.state = .extracting(progress: 1.0)

            guard !extractedFiles.isEmpty else {
                throw AppError.noImagesFound
            }

            // Convert any files not already in the target format
            let format = settings.format
            let needsConversion = extractedFiles.contains { file in
                !format.matches(fileExtension: file.pathExtension)
            }
            if needsConversion {
                logger.info("Converting \(extractedFiles.count) files to \(format.displayName)")
                item.state = .converting(progress: 0)
                let converter = ImageConverter(cjxlURL: settings.cjxlURL)
                extractedFiles = try await converter.convert(
                    files: extractedFiles,
                    to: format,
                    outputDirectory: outputDir
                ) { progress in
                    item.state = .converting(progress: progress)
                }
                logger.info("Conversion complete: \(extractedFiles.count) files")
            } else {
                logger.info("No conversion needed, all files already in \(format.displayName)")
            }

            item.extractedImageCount = extractedFiles.count

            // Write IPTC metadata if enabled
            if settings.metadata.metadataEnabled {
                guard let exiftoolURL = settings.exiftoolURL else {
                    throw AppError.exiftoolNotFound
                }
                logger.info("Writing metadata to \(extractedFiles.count) files")
                item.state = .writingMetadata(progress: 0)
                let writer = MetadataWriter(exiftoolURL: exiftoolURL)
                try await writer.writeMetadata(
                    to: extractedFiles,
                    configuration: settings.metadata,
                    documentFileName: item.fileName
                ) { progress in
                    item.state = .writingMetadata(progress: progress)
                }
                logger.info("Metadata writing complete")
            }

            // OCR for PDFs if enabled
            if settings.ocrEnabled && item.documentType == .pdf {
                logger.info("Starting OCR on \(item.fileName)")
                item.state = .runningOCR(progress: 0)
                let ocrService = OCRService()
                let sourceURL = item.sourceURL
                let ocrResults = try await ocrService.performOCR(on: sourceURL) { progress in
                    item.state = .runningOCR(progress: progress)
                }

                if !ocrResults.isEmpty {
                    let stem = item.sourceURL.deletingPathExtension().lastPathComponent
                    let searchablePDFURL = outputDir.appendingPathComponent(
                        "\(stem)_searchable.pdf"
                    )
                    let builder = SearchablePDFBuilder()
                    try builder.build(
                        from: item.sourceURL,
                        ocrResults: ocrResults,
                        outputURL: searchablePDFURL
                    )
                    logger.info("Searchable PDF created with \(ocrResults.count) pages of text")
                }
            }

            logger.info("Completed: \(item.fileName) — \(extractedFiles.count) images")
            item.state = .completed(imageCount: extractedFiles.count)
        } catch {
            logger.error("Failed: \(item.fileName) — \(error.localizedDescription)")
            item.state = .failed(message: error.localizedDescription)
        }
    }
}
