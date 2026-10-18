import Foundation

struct LegacyOfficeImageExtractor {
    func extract(documentURL: URL, to outputDirectory: URL, documentName: String) async throws -> [URL] {
        let compound = try CompoundDocument(data: Data(contentsOf: documentURL, options: .mappedIfSafe))
        guard try compound.stream(named: "EncryptedPackage") == nil,
              try compound.stream(named: "EncryptionInfo") == nil else {
            throw CompoundDocument.invalid("Password-encrypted documents are not supported")
        }
        var sources: [Data] = []
        switch DocumentType(url: documentURL) {
        case .doc:
            guard let word = try compound.stream(named: "WordDocument"), word.count >= 32,
                  word.le16(0) == 0xA5EC, word.le16(2) >= 0xC1 else {
                throw CompoundDocument.invalid("Only Word 97–2003 binary documents are supported")
            }
            guard word.le16(10) & 0x8100 == 0 else { throw CompoundDocument.invalid("Encrypted Word documents are not supported") }
            sources.append(word)
            for name in ["Data", "0Table", "1Table"] {
                if let stream = try compound.stream(named: name) { sources.append(stream) }
            }
        case .ppt:
            guard try compound.stream(named: "PowerPoint Document") != nil else {
                throw CompoundDocument.invalid("Missing PowerPoint document stream")
            }
            // Encryption changes the Current User token (MS-PPT CurrentUserAtom).
            if let user = try compound.stream(named: "Current User"), user.count >= 16,
               user.le32(12) == 0xF3D1C4DF {
                throw CompoundDocument.invalid("Encrypted PowerPoint documents are not supported")
            }
            if let pictures = try compound.stream(named: "Pictures") { sources.append(pictures) }
        case .xls:
            guard let workbook = try compound.stream(named: "Workbook") else {
                throw CompoundDocument.invalid("Only Excel 97–2003 BIFF8 workbooks are supported")
            }
            guard workbook.count >= 8, workbook.le16(0) == 0x0809, workbook.le16(4) == 0x0600 else {
                throw CompoundDocument.invalid("Only Excel 97–2003 BIFF8 workbooks are supported")
            }
            var drawing = Data()
            var collecting = false
            var offset = 0
            while offset + 4 <= workbook.count {
                let type = workbook.le16(offset)
                let length = Int(workbook.le16(offset + 2))
                guard length <= workbook.count - offset - 4 else { throw CompoundDocument.invalid("Truncated BIFF record") }
                if type == 0x002F { throw CompoundDocument.invalid("Encrypted Excel workbooks are not supported") }
                if type == 0x00EB { collecting = true }
                else if type != 0x003C { collecting = false }
                if collecting { drawing.append(workbook.subdata(in: offset + 4..<offset + 4 + length)) }
                offset += 4 + length
            }
            guard offset == workbook.count else { throw CompoundDocument.invalid("Incomplete BIFF record") }
            sources.append(drawing)
        default: throw CompoundDocument.invalid("Unsupported legacy Office format")
        }
        var images: [(Data, String)] = []
        var seen: Set<Data> = []
        for source in sources {
            for image in try OfficeArtImageParser.images(in: source) where seen.insert(image.0).inserted {
                images.append(image)
            }
        }
        guard !images.isEmpty else { throw AppError.noImagesFound }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        return try images.enumerated().map { index, image in
            let output = outputDirectory.appendingPathComponent(String(format: "%@_I%03d.%@", documentName, index + 1, image.1))
            try image.0.write(to: output, options: .withoutOverwriting)
            return output
        }
    }
}
