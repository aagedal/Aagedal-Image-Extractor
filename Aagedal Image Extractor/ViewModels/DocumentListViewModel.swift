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
    var pdfimagesURL: URL?
    var homebrewInstalled: Bool = HomebrewService.isInstalled
    var isInstallingPoppler: Bool = false
    var installError: String?
    var setupDismissed: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    var exiftoolAvailable: Bool { exiftoolURL != nil }
    var pdfimagesAvailable: Bool { pdfimagesURL != nil }
    var hasDocuments: Bool { !documents.isEmpty }
    var hasPendingDocuments: Bool { documents.contains { $0.state == .pending } }
    var isProcessing: Bool { documents.contains { $0.state.isProcessing } }

    private static let metadataConfigKey = "MetadataConfiguration"
    private static let exportFormatKey = "ExportFormat"

    init() {
        pdfimagesURL = PdfImagesLocator.locate()
        exiftoolURL = ExiftoolLocator.locate()
        if let data = UserDefaults.standard.data(forKey: Self.metadataConfigKey),
           let saved = try? JSONDecoder().decode(MetadataConfiguration.self, from: data) {
            metadataConfiguration = saved
        }
        if let raw = UserDefaults.standard.string(forKey: Self.exportFormatKey),
           let saved = ExportFormat(rawValue: raw) {
            selectedFormat = saved
        }
    }

    func saveFormatSelection() {
        UserDefaults.standard.set(selectedFormat.rawValue, forKey: Self.exportFormatKey)
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
        pdfimagesURL = PdfImagesLocator.locate()
        exiftoolURL = ExiftoolLocator.locate()
        installError = nil
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

    func processAll() async {
        let pending = documents.filter { $0.state == .pending }
        for item in pending {
            await processSingle(item)
        }
    }

    private func processSingle(_ item: DocumentItem) async {
        let outputDir = item.defaultOutputDirectory
        item.outputDirectoryURL = outputDir
        item.state = .extracting(progress: 0)
        logger.info("Starting processing: \(item.fileName)")

        do {
            var extractedFiles: [URL]

            switch item.documentType {
            case .pdf:
                guard let pdfimagesURL else {
                    throw AppError.pdfimagesNotFound
                }
                let extractor = PDFImageExtractor(pdfimagesURL: pdfimagesURL)
                extractedFiles = try await extractor.extract(
                    pdfURL: item.sourceURL,
                    to: outputDir,
                    format: selectedFormat
                )
                logger.info("Extracted \(extractedFiles.count) files from PDF")
            case .docx:
                let extractor = DOCXImageExtractor()
                extractedFiles = try await extractor.extract(
                    docxURL: item.sourceURL,
                    to: outputDir
                )
                logger.info("Extracted \(extractedFiles.count) files from DOCX")
            }

            item.state = .extracting(progress: 1.0)

            guard !extractedFiles.isEmpty else {
                throw AppError.noImagesFound
            }

            // Convert any files not already in the target format
            let format = selectedFormat
            let needsConversion = extractedFiles.contains { file in
                let ext = file.pathExtension.lowercased()
                switch format {
                case .jpeg: return ext != "jpg" && ext != "jpeg"
                case .tiff: return ext != "tiff" && ext != "tif"
                case .jpegXL: return ext != "jxl"
                }
            }
            if needsConversion {
                logger.info("Converting \(extractedFiles.count) files to \(format.displayName)")
                item.state = .converting(progress: 0)
                let converter = ImageConverter()
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
            if metadataConfiguration.metadataEnabled {
                guard let exiftoolURL else {
                    throw AppError.exiftoolNotFound
                }
                logger.info("Writing metadata to \(extractedFiles.count) files")
                item.state = .writingMetadata(progress: 0)
                let writer = MetadataWriter(exiftoolURL: exiftoolURL)
                try await writer.writeMetadata(
                    to: extractedFiles,
                    configuration: metadataConfiguration,
                    documentFileName: item.fileName
                ) { progress in
                    item.state = .writingMetadata(progress: progress)
                }
                logger.info("Metadata writing complete")
            }

            // OCR for PDFs if enabled
            if ocrEnabled && item.documentType == .pdf {
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
