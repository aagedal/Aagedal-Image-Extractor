import AppKit
import Foundation

// Batch checks never need conversion. Keep this runner independent of the JXL package;
// an unexpected conversion indicates the active batch picked up the changed format.
struct ImageConverter {
    init(cjxlURL: URL? = nil) {}
    func convert(files: [URL], to format: ExportFormat, outputDirectory: URL,
                 progressHandler: @MainActor (Double) -> Void) async throws -> [URL] {
        throw AppError.conversionFailed("Batch format changed while extraction was suspended")
    }
}

@main
struct BatchProcessingChecks {
    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Hold the real extraction subprocess until settings and the queue are edited.
        // The bounded wait also prevents a failed test from leaving a child running.
        let tool = root.appendingPathComponent("pdfimages")
        try Data("""
        #!/bin/sh
        touch "$0.started"
        count=0
        while [ ! -f "$0.continue" ]; do
            count=$((count + 1))
            [ "$count" -lt 500 ] || exit 9
            sleep 0.01
        done
        for root do :; done
        printf 'image' > "$root-001-000.png"
        """.utf8).write(to: tool)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        let model = DocumentListViewModel()
        model.selectedFormat = .png
        model.outputDestination = .customDirectory
        let originalOutput = root.appendingPathComponent("original-output")
        model.customOutputDirectoryURL = originalOutput
        model.ocrEnabled = false
        model.metadataConfiguration.metadataEnabled = false
        model.pdfimagesURL = tool
        model.addDocuments(urls: ["first.pdf", "removed.pdf", "last.pdf"].map {
            root.appendingPathComponent($0)
        })
        let originalItems = model.documents
        let batch = Task { await model.processAll() }
        let deadline = Date().addingTimeInterval(10)
        while !fm.fileExists(atPath: tool.path + ".started"), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard fm.fileExists(atPath: tool.path + ".started") else {
            try Data().write(to: URL(fileURLWithPath: tool.path + ".continue"))
            await batch.value
            preconditionFailure("Extraction did not start")
        }
        precondition(model.isProcessing)
        originalItems[1].state = .failed(message: "Controlled failure")
        model.retryDocument(originalItems[1])
        precondition(originalItems[1].state == .failed(message: "Controlled failure"),
                     "Retry must not alter an active batch")
        originalItems[1].state = .pending
        model.selectedFormat = .tiff
        model.ocrEnabled = true
        model.metadataConfiguration.metadataEnabled = true
        model.pdfimagesURL = nil
        model.exiftoolURL = nil
        let changedOutput = root.appendingPathComponent("changed-output")
        model.customOutputDirectoryURL = changedOutput
        model.outputDestination = .nextToOriginals
        model.removeDocument(originalItems[0])
        precondition(model.documents.contains { $0.id == originalItems[0].id },
                     "The active document must remain visible")
        model.removeDocument(originalItems[1])
        model.addDocuments(urls: [root.appendingPathComponent("added.pdf")])
        await model.processAll()
        precondition(model.documents.last?.state == .pending,
                     "A second processAll call must not start a concurrent batch")
        try Data().write(to: URL(fileURLWithPath: tool.path + ".continue"))
        await batch.value

        precondition(!model.isProcessing)
        for item in [originalItems[0], originalItems[2]] {
            precondition(item.state == .completed(imageCount: 1), "Original batch settings must be used")
            precondition(item.outputDirectoryURL?.deletingLastPathComponent().path == originalOutput.path)
        }
        precondition(originalItems[1].state == .pending && originalItems[1].outputDirectoryURL == nil,
                     "Removed queued documents must not be processed")
        precondition(model.documents.last?.state == .pending,
                     "Documents added during processing belong to the next batch")
        precondition(!fm.fileExists(atPath: changedOutput.path))

        // Updated settings take effect when the next batch begins, and failure resets the busy flag.
        await model.processAll()
        guard case .failed = model.documents.last!.state else {
            preconditionFailure("The next batch should use the updated missing-tool setting")
        }
        precondition(!model.isProcessing)
        let failedItem = model.documents.last!
        let previousOutput = failedItem.outputDirectoryURL!
        let marker = previousOutput.appendingPathComponent("partial.txt")
        try Data("preserve partial output".utf8).write(to: marker)
        failedItem.extractedImageCount = 9
        model.retryDocument(failedItem)
        precondition(failedItem.state == .pending && failedItem.extractedImageCount == 0)
        precondition(failedItem.outputDirectoryURL == previousOutput, "Partial output stays accessible while queued")
        model.pdfimagesURL = tool
        model.selectedFormat = .original
        model.ocrEnabled = false
        model.metadataConfiguration.metadataEnabled = false
        await model.processAll()
        precondition(failedItem.state == .completed(imageCount: 1), "Retry uses updated settings")
        precondition(failedItem.outputDirectoryURL != previousOutput, "Retry must use a fresh directory")
        precondition(fm.fileExists(atPath: marker.path), "Retry preserves partial output from the previous attempt")
        model.retryDocument(failedItem)
        precondition(failedItem.state == .completed(imageCount: 1), "Completed documents cannot be retried")
        model.removeDocument(originalItems[0])
        precondition(!model.documents.contains { $0.id == originalItems[0].id })
        // Original mode must bypass the converter even for images AppKit cannot decode.
        let archiveRoot = root.appendingPathComponent("original-archive")
        try fm.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        let vectorBytes = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        try vectorBytes.write(to: archiveRoot.appendingPathComponent("vector.svg"))
        let archive = root.appendingPathComponent("vectors.zip")
        let zip = try await runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-q", archive.path, "vector.svg"], currentDirectoryURL: archiveRoot)
        precondition(zip.exitCode == 0)
        let originalModel = DocumentListViewModel()
        originalModel.selectedFormat = .original
        originalModel.outputDestination = .nextToOriginals
        originalModel.ocrEnabled = false
        originalModel.metadataConfiguration.metadataEnabled = false
        originalModel.addDocuments(urls: [archive])
        await originalModel.processAll()
        let originalItem = originalModel.documents[0]
        precondition(originalItem.state == .completed(imageCount: 1))
        let vector = originalItem.outputDirectoryURL!.appendingPathComponent("vectors_I001.svg")
        let exportedBytes = try Data(contentsOf: vector)
        precondition(exportedBytes == vectorBytes)
        let importModel = DocumentListViewModel()
        let importURLs = (0..<2000).map { root.appendingPathComponent("import-\($0).pdf") }
        importModel.addDocuments(urls: importURLs + importURLs)
        importModel.addDocuments(urls: [root.appendingPathComponent("nested/../import-0.pdf"), root.appendingPathComponent("unsupported.txt")])
        precondition(importModel.documents.map(\.sourceURL) == importURLs,
                     "Large imports preserve order, reject unsupported files and deduplicate equivalent paths")
        let removed = importModel.documents[0]
        importModel.removeDocument(removed)
        removed.state = .failed(message: "Removed")
        importModel.retryDocument(removed)
        precondition(removed.state == .failed(message: "Removed"), "Removed items cannot be queued again")
        print("Passed: retry guards, changed settings, partial output preservation and 2,000-file import deduplication.")
        print("Passed: original archive export bypasses raster conversion in the real batch pipeline.")
        print("Passed: batch settings snapshot, tool/output preservation, reentry guard, active removal guard, queued removal, deferred additions and busy-state reset.")
    }
}
