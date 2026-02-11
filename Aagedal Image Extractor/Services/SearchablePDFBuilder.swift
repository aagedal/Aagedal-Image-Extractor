import AppKit
import CoreText
import Foundation
import PDFKit
import Vision

struct SearchablePDFBuilder {
    func build(
        from originalPDFURL: URL,
        ocrResults: [OCRResult],
        outputURL: URL
    ) throws {
        guard let document = PDFDocument(url: originalPDFURL) else {
            throw AppError.ocrFailed("Cannot open original PDF for searchable overlay")
        }

        let resultsByPage = Dictionary(grouping: ocrResults, by: \.pageIndex)

        let outputDocument = PDFDocument()

        for i in 0..<document.pageCount {
            guard let originalPage = document.page(at: i) else { continue }
            let observations = resultsByPage[i]?.first?.observations ?? []
            let overlayPage = SearchableOverlayPage(
                originalPage: originalPage,
                observations: observations
            )
            outputDocument.insert(overlayPage, at: outputDocument.pageCount)
        }

        guard outputDocument.write(to: outputURL) else {
            throw AppError.ocrFailed("Failed to write searchable PDF")
        }
    }
}

private final class SearchableOverlayPage: PDFPage {
    private let originalPage: PDFPage
    private let observations: [VNRecognizedTextObservation]

    init(originalPage: PDFPage, observations: [VNRecognizedTextObservation]) {
        self.originalPage = originalPage
        self.observations = observations
        super.init()
    }

    override func bounds(for box: PDFDisplayBox) -> CGRect {
        originalPage.bounds(for: box)
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        let pageRect = originalPage.bounds(for: box)

        // Draw the original page
        context.saveGState()
        originalPage.draw(with: box, to: context)
        context.restoreGState()

        // Overlay invisible OCR text
        context.saveGState()
        context.setTextDrawingMode(.invisible)

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string

            // Vision uses normalized coordinates (0-1) with origin at bottom-left
            let boundingBox = observation.boundingBox
            let x = boundingBox.origin.x * pageRect.width
            let y = boundingBox.origin.y * pageRect.height
            let width = boundingBox.width * pageRect.width
            let height = boundingBox.height * pageRect.height

            let fontSize = height * 0.85
            guard fontSize > 0 else { continue }

            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
            ]
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)

            context.saveGState()
            context.textPosition = CGPoint(x: x, y: y)

            // Scale text to fit the bounding box width
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            if lineWidth > 0 {
                let scaleX = width / lineWidth
                context.textMatrix = CGAffineTransform(scaleX: scaleX, y: 1.0)
                context.textPosition = CGPoint(x: x, y: y)
            }

            CTLineDraw(line, context)
            context.restoreGState()
        }

        context.restoreGState()
    }
}
