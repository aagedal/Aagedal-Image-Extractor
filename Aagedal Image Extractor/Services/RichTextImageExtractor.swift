import AppKit
import Foundation

struct RichTextImageExtractor {
    @MainActor
    func extract(documentURL: URL, to outputDirectory: URL, documentName: String) throws -> [URL] {
        let fm = FileManager.default
        let type: NSAttributedString.DocumentType = documentURL.pathExtension.lowercased() == "rtfd" ? .rtfd : .rtf
        if type == .rtf {
            let images = try RTFImageParser.images(in: Data(contentsOf: documentURL))
            return try write(images, to: outputDirectory, documentName: documentName)
        }
        if type == .rtfd {
            // Do not follow package symlinks while importing attachments.
            let keys: [URLResourceKey] = [.isSymbolicLinkKey]
            guard let contents = fm.enumerator(at: documentURL, includingPropertiesForKeys: keys) else {
                throw AppError.fileAccessDenied(documentURL.path)
            }
            for case let url as URL in contents {
                if try url.resourceValues(forKeys: Set(keys)).isSymbolicLink == true {
                    throw AppError.conversionFailed("RTFD packages containing symbolic links are not supported")
                }
            }
        }
        let text = try NSAttributedString(url: documentURL, options: [.documentType: type], documentAttributes: nil)
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var images: [(Data, String)] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            if let wrapper = attachment.fileWrapper, let data = wrapper.regularFileContents {
                let ext = ((wrapper.preferredFilename ?? wrapper.filename ?? "") as NSString).pathExtension.lowercased()
                // RTFD can also contain arbitrary file attachments. Export images only.
                if ArchiveImageExtractor.imageExtensions.contains(ext) {
                    images.append((data, ext))
                } else if let bitmap = NSBitmapImageRep(data: data),
                          let png = bitmap.representation(using: .png, properties: [:]) {
                    images.append((png, "png"))
                }
            } else if let data = attachment.image?.tiffRepresentation {
                images.append((data, "tiff"))
            }
        }
        return try write(images, to: outputDirectory, documentName: documentName)
    }

    private func write(_ images: [(Data, String)], to outputDirectory: URL, documentName: String) throws -> [URL] {
        guard !images.isEmpty else { throw AppError.noImagesFound }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        return try images.enumerated().map { index, image in
            let output = outputDirectory.appendingPathComponent(
                String(format: "%@_I%03d.%@", documentName, index + 1, image.1))
            try image.0.write(to: output, options: .atomic)
            return output
        }
    }
}
