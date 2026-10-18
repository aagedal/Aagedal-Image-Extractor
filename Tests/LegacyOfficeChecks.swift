import Foundation
import zlib

/// Controlled binary fixtures exercise sector allocation independently of image record parsing.
enum LegacyOfficeChecks {
    static func u16(_ value: Int) -> Data { Data([UInt8(value & 255), UInt8((value >> 8) & 255)]) }
    static func u32(_ value: Int) -> Data { u16(value & 65535) + u16((value >> 16) & 65535) }
    static func set(_ data: inout Data, _ offset: Int, _ value: Int, width: Int = 4) {
        data.replaceSubrange(offset..<offset + width, with: width == 2 ? u16(value) : u32(value))
    }
    static func blip(_ png: Data, dual: Bool = false) -> Data {
        let payload = Data(count: dual ? 32 : 16) + Data([255]) + png
        return u16((dual ? 0x6E1 : 0x6E0) << 4) + u16(0xF01E) + u32(payload.count) + payload
    }
    static func biff(_ type: Int, _ payload: Data) -> Data { u16(type) + u16(payload.count) + payload }

    static func compound(_ streams: [(String, Data)], version: Int = 3) -> Data {
        let size = version == 3 ? 512 : 4096
        var blocks: [Data] = []
        var fat: [Int] = []
        func allocate(_ data: Data) -> Int {
            if data.isEmpty { return 0xFFFFFFFE }
            let start = blocks.count
            let count = (data.count + size - 1) / size
            for i in 0..<count {
                var block = Data(data.dropFirst(i * size).prefix(size))
                block.append(Data(count: size - block.count))
                blocks.append(block)
                fat.append(i + 1 == count ? 0xFFFFFFFE : start + i + 1)
            }
            return start
        }
        var mini = Data()
        var miniFat: [Int] = []
        var locations: [Int] = []
        for (_, stream) in streams {
            if stream.count >= 4096 { locations.append(allocate(stream)); continue }
            if stream.isEmpty { locations.append(0xFFFFFFFE); continue }
            let start = miniFat.count
            let count = (stream.count + 63) / 64
            locations.append(start)
            mini.append(stream)
            mini.append(Data(count: count * 64 - stream.count))
            for i in 0..<count { miniFat.append(i + 1 == count ? 0xFFFFFFFE : start + i + 1) }
        }
        let miniStart = allocate(mini)
        var table = miniFat.reduce(into: Data()) { $0.append(u32($1)) }
        if !table.isEmpty { table.append(Data(repeating: 255, count: (size - table.count % size) % size)) }
        let miniTableStart = allocate(table)
        var directory = Data(count: ((streams.count + 1) * 128 + size - 1) / size * size)
        func entry(_ id: Int, _ name: String, _ kind: Int, _ start: Int, _ length: Int) {
            let offset = id * 128
            let text = name.data(using: .utf16LittleEndian)! + Data([0,0])
            directory.replaceSubrange(offset..<offset + text.count, with: text)
            set(&directory, offset + 64, text.count, width: 2)
            directory[offset + 66] = UInt8(kind)
            directory[offset + 67] = 1
            set(&directory, offset + 68, 0xFFFFFFFF)
            set(&directory, offset + 72, id > 0 && id < streams.count ? id + 1 : 0xFFFFFFFF)
            set(&directory, offset + 76, id == 0 && !streams.isEmpty ? 1 : 0xFFFFFFFF)
            set(&directory, offset + 116, start)
            set(&directory, offset + 120, length)
        }
        entry(0, "Root Entry", 5, miniStart, mini.count)
        for (i, stream) in streams.enumerated() { entry(i + 1, stream.0, 2, locations[i], stream.1.count) }
        let directoryStart = allocate(directory)
        let fatStart = blocks.count
        let fatCount = (fat.count + size / 4 - 2) / (size / 4 - 1)
        fat += Array(repeating: 0xFFFFFFFD, count: fatCount)
        fat += Array(repeating: 0xFFFFFFFF, count: fatCount * size / 4 - fat.count)
        let fatBytes = fat.reduce(into: Data()) { $0.append(u32($1)) }
        for i in 0..<fatCount { blocks.append(fatBytes.subdata(in: i * size..<(i + 1) * size)) }
        var header = Data(count: size)
        header.replaceSubrange(0..<8, with: [0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1])
        set(&header, 26, version, width: 2)
        set(&header, 28, 0xFFFE, width: 2)
        set(&header, 30, version == 3 ? 9 : 12, width: 2)
        set(&header, 32, 6, width: 2)
        set(&header, 44, fatCount)
        set(&header, 48, directoryStart)
        set(&header, 56, 4096)
        set(&header, 60, miniTableStart)
        set(&header, 64, table.count / size)
        set(&header, 68, 0xFFFFFFFE)
        for i in 0..<109 { set(&header, 76 + i * 4, i < fatCount ? fatStart + i : 0xFFFFFFFF) }
        return blocks.reduce(into: header) { $0.append($1) }
    }

    static func run(root: URL, png: Data) async throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: message, code: 1) }
        }
        func rejected(_ data: Data, _ ext: String, _ label: String) async throws {
            let url = root.appendingPathComponent("reject-\(label).\(ext)")
            try data.write(to: url)
            do {
                _ = try await LegacyOfficeImageExtractor().extract(documentURL: url,
                    to: root.appendingPathComponent("reject-output-\(label)"), documentName: label)
            } catch AppError.invalidArchive { return }
            throw NSError(domain: "Expected rejection: \(label)", code: 1)
        }
        var word = Data(count: 32)
        set(&word, 0, 0xA5EC, width: 2)
        set(&word, 2, 0xC1, width: 2)
        let picture = blip(png, dual: true)
        let workbook = biff(0x0809, u16(0x0600) + u16(5))
            + biff(0x00EB, Data(picture.prefix(19))) + biff(0x003C, Data(picture.dropFirst(19))) + biff(0x000A, Data())
        for version in [3,4] {
            for (ext, streams) in [
                ("doc", [("WordDocument", word), ("Data", Data(count: 4090) + picture), ("1Table", picture)]),
                ("ppt", [("PowerPoint Document", Data(count: 4096)), ("Pictures", picture)]),
                ("xls", [("Workbook", workbook)]),
            ] {
                let url = root.appendingPathComponent("native-\(version).\(ext)")
                try compound(streams, version: version).write(to: url)
                let images = try await LegacyOfficeImageExtractor().extract(documentURL: url,
                    to: root.appendingPathComponent("native-\(version)-\(ext)"), documentName: "native")
                let actual = try Data(contentsOf: images[0])
                try check(images.count == 1 && actual == png && images[0].lastPathComponent == "native_I001.png",
                          "Native \(ext) version \(version) preserves bytes and deduplicates")
            }
        }
        var encryptedWord = word
        set(&encryptedWord, 10, 0x100, width: 2)
        try await rejected(compound([("WordDocument", encryptedWord), ("Data", picture)]), "doc", "encrypted-word")
        try await rejected(compound([("Workbook", biff(0x0809, u16(0x0600) + u16(5)) + biff(0x002F, Data()))]), "xls", "encrypted-excel")
        var current = Data(count: 16)
        set(&current, 12, 0xF3D1C4DF)
        try await rejected(compound([("PowerPoint Document", Data()), ("Current User", current), ("Pictures", picture)]), "ppt", "encrypted-ppt")
        try await rejected(Data("Not an OLE file".utf8), "doc", "invalid-header")
        var cyclic = compound([("Workbook", Data(count: 4096))])
        let fatSector = Int(cyclic.le32(76))
        set(&cyclic, (fatSector + 1) * 512, 0)
        try await rejected(cyclic, "xls", "cyclic-fat")
        var miniCycle = compound([("WordDocument", word), ("Data", picture)])
        let miniTable = (Int(miniCycle.le32(60)) + 1) * 512
        set(&miniCycle, miniTable + 4, 1)
        try await rejected(miniCycle, "doc", "cyclic-mini-fat")
        var directoryCycle = compound([("WordDocument", word)])
        let directoryOffset = (Int(directoryCycle.le32(48)) + 1) * 512
        set(&directoryCycle, directoryOffset + 128 + 72, 1)
        try await rejected(directoryCycle, "doc", "cyclic-directory")
        var oversized = compound([("WordDocument", word)])
        let oversizedDirectory = (Int(oversized.le32(48)) + 1) * 512
        set(&oversized, oversizedDirectory + 128 + 120, 0xFFFFFFFF)
        try await rejected(oversized, "doc", "oversized-stream")
        // Exercise an external DIFAT sector without allocating a multi-megabyte fixture.
        var externalDIFAT = compound([("WordDocument", word), ("Data", picture)])
        var difatBlock = Data(repeating: 255, count: 512)
        set(&difatBlock, 0, Int(externalDIFAT.le32(76)))
        set(&difatBlock, 508, 0xFFFFFFFE)
        set(&externalDIFAT, 68, externalDIFAT.count / 512 - 1)
        set(&externalDIFAT, 72, 1)
        set(&externalDIFAT, 76, 0xFFFFFFFF)
        externalDIFAT.append(difatBlock)
        let externalStorage = try CompoundDocument(data: externalDIFAT)
        let externalPicture = try externalStorage.stream(named: "Data")
        try check(externalPicture == picture, "External DIFAT sector")
        try await rejected(compound([("WordDocument", word), ("Data", Data(picture.dropLast()))]), "doc", "truncated-blip")
        try await rejected(compound([("Workbook", workbook + Data([1]))]), "xls", "truncated-biff")
        let empty = root.appendingPathComponent("no-pictures.doc")
        try compound([("WordDocument", word)]).write(to: empty)
        do {
            _ = try await LegacyOfficeImageExtractor().extract(documentURL: empty,
                to: root.appendingPathComponent("empty-native"), documentName: "empty")
            throw NSError(domain: "Expected no images", code: 1)
        } catch AppError.noImagesFound {}
        // A zlib-compressed metafile is restored to its original uncompressed bytes.
        let vector = Data(repeating: 42, count: 512)
        var packed = Data(count: Int(compressBound(uLong(vector.count))))
        var packedSize = uLongf(packed.count)
        let status = packed.withUnsafeMutableBytes { output in
            vector.withUnsafeBytes { input in
                compress(output.bindMemory(to: Bytef.self).baseAddress!, &packedSize,
                         input.bindMemory(to: Bytef.self).baseAddress!, uLong(vector.count))
            }
        }
        try check(status == Z_OK, "Create compressed vector fixture")
        packed.count = Int(packedSize)
        var meta = Data(count: 34)
        set(&meta, 0, vector.count)
        set(&meta, 28, packed.count)
        meta[33] = 0xFE
        let body = Data(count: 16) + meta + packed
        let record = u16(0x3D4 << 4) + u16(0xF01A) + u32(body.count) + body
        let decoded = try OfficeArtImageParser.images(in: record)
        try check(decoded.count == 1 && decoded[0].0 == vector && decoded[0].1 == "emf", "Metafile decompression")
        var uncompressedHeader = meta
        set(&uncompressedHeader, 28, vector.count)
        uncompressedHeader[32] = 0xFE
        let uncompressedBody = Data(count: 32) + uncompressedHeader + vector
        let uncompressedRecord = u16(0x217 << 4) + u16(0xF01B) + u32(uncompressedBody.count) + uncompressedBody
        let uncompressed = try OfficeArtImageParser.images(in: uncompressedRecord)
        try check(uncompressed[0].0 == vector && uncompressed[0].1 == "wmf", "Uncompressed dual-UID metafile")
        var oversizedRecord = record
        set(&oversizedRecord, 24, 128 * 1024 * 1024 + 1)
        do {
            _ = try OfficeArtImageParser.images(in: oversizedRecord)
            throw NSError(domain: "Expected decompression size limit", code: 1)
        } catch AppError.invalidArchive {}
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LegacyOffice")
        for (name, extensions) in [
            ("PngPicture.doc", ["png"]),
            ("pictures.ppt", ["jpg", "png", "wmf", "pict", "emf"]),
            ("SimpleWithImages.xls", ["jpg", "png", "wmf", "emf"]),
        ] {
            let files = try await LegacyOfficeImageExtractor().extract(
                documentURL: fixtures.appendingPathComponent(name),
                to: root.appendingPathComponent("real-" + name), documentName: "real")
            try check(files.map(\.pathExtension).sorted() == extensions.sorted(), "Real Office fixture: \(name)")
        }
        print("Native legacy Office checks passed")
    }
}
