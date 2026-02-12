import Foundation
import PDFKit
@preconcurrency import Vision

struct OCRResult: @unchecked Sendable {
    let pageIndex: Int
    let observations: [VNRecognizedTextObservation]
}

struct OCRService {
    private static let renderDPI: CGFloat = 300.0
    nonisolated private static let supportedLanguages = ["en", "no", "da", "sv", "de", "fr"]

    // Page rendering uses PDFKit/NSImage which require the main thread
    func performOCR(
        on pdfURL: URL,
        progressHandler: @MainActor (Double) -> Void
    ) async throws -> [OCRResult] {
        guard let document = PDFDocument(url: pdfURL) else {
            throw AppError.ocrFailed("Cannot open PDF document")
        }

        let pageCount = document.pageCount
        var results: [OCRResult] = []

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }

            let cgImage = renderPage(page)

            if let cgImage {
                let observations = try await recognizeText(in: cgImage)
                if !observations.isEmpty {
                    results.append(OCRResult(pageIndex: i, observations: observations))
                }
            }

            progressHandler(Double(i + 1) / Double(pageCount))
        }

        return results
    }

    private func renderPage(_ page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale = Self.renderDPI / 72.0
        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }

    nonisolated private func recognizeText(
        in image: CGImage
    ) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let request = VNRecognizeTextRequest { request, error in
                guard !hasResumed else { return }
                hasResumed = true
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations =
                    request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: observations)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = Self.supportedLanguages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(throwing: error)
            }
        }
    }
}
