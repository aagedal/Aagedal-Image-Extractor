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
        print("Passed: original archive export bypasses raster conversion in the real batch pipeline.")
        print("Passed: batch settings snapshot, tool/output preservation, reentry guard, active removal guard, queued removal, deferred additions and busy-state reset.")
    }
}
