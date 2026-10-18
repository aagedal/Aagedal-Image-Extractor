import Foundation
import zlib

/// MS-ODRAW BLIP records. Only recognized record headers and image signatures are accepted.
// Specification: https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/
struct OfficeArtImageParser {
    static func images(in data: Data) throws -> [(Data, String)] {
        var images: [(Data, String)] = []
        var offset = 0
        while offset + 8 <= data.count {
            let options = Int(data.le16(offset))
            let type = data.le16(offset + 2)
            let instance = options >> 4
            let specification: (Int, String)?
            switch type {
            case 0xF01A: specification = (0x3D4, "emf")
            case 0xF01B: specification = (0x216, "wmf")
            case 0xF01C: specification = (0x542, "pict")
            case 0xF01D, 0xF02A: specification = (instance >= 0x6E2 ? 0x6E2 : 0x46A, "jpg")
            case 0xF01E: specification = (0x6E0, "png")
            case 0xF01F: specification = (0x7A8, "dib")
            case 0xF029: specification = (0x6E4, "tiff")
            default: specification = nil
            }
            guard let (base, ext) = specification, options & 15 == 0,
                  instance == base || instance == base + 1 else { offset += 1; continue }
            let length = Int(data.le32(offset + 4))
            let uidSize = instance == base ? 16 : 32
            let vector = ["emf", "wmf", "pict"].contains(ext)
            let overhead = uidSize + (vector ? 34 : 1)
            guard length > overhead, length <= data.count - offset - 8 else {
                throw CompoundDocument.invalid("Truncated OfficeArt image record")
            }
            let start = offset + 8 + overhead
            var payload = data.subdata(in: start..<offset + 8 + length)
            if vector {
                let header = offset + 8 + uidSize
                let unpacked = Int(data.le32(header))
                let packed = Int(data.le32(header + 28))
                let compression = data[header + 32]
                guard packed == payload.count, unpacked > 0, unpacked <= 128 * 1024 * 1024 else {
                    throw CompoundDocument.invalid("Invalid or oversized metafile")
                }
                if compression == 0 {
                    var decoded = Data(count: unpacked)
                    var count = uLongf(unpacked)
                    let status = decoded.withUnsafeMutableBytes { output in
                        payload.withUnsafeBytes { input in
                            uncompress(output.bindMemory(to: Bytef.self).baseAddress!, &count,
                                       input.bindMemory(to: Bytef.self).baseAddress!, uLong(payload.count))
                        }
                    }
                    guard status == Z_OK, count == unpacked else { throw CompoundDocument.invalid("Invalid compressed metafile") }
                    payload = decoded
                } else if compression != 0xFE || unpacked != payload.count {
                    throw CompoundDocument.invalid("Unsupported metafile compression")
                }
            } else {
                let valid: Bool
                switch ext {
                case "png": valid = payload.starts(with: [137,80,78,71,13,10,26,10])
                case "jpg": valid = payload.starts(with: [255,216,255])
                case "tiff": valid = payload.starts(with: [73,73,42,0]) || payload.starts(with: [77,77,0,42])
                case "dib": valid = payload.count >= 12 && [12,40,52,56,108,124].contains(Int(payload.le32(0)))
                default: valid = false
                }
                guard valid else { throw CompoundDocument.invalid("Invalid \(ext.uppercased()) image payload") }
            }
            images.append((payload, ext))
            offset += 8 + length
        }
        return images
    }
}
