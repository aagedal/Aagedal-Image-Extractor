import Foundation

/// Reads standard RTF picture groups without rendering or transcoding the image data.
struct RTFImageParser {
    static func images(in data: Data) throws -> [(Data, String)] {
        let bytes = Array(data)
        guard bytes.starts(with: Array("{\\rtf".utf8)) else {
            throw AppError.conversionFailed("Invalid RTF document")
        }
        var index = 0
        var depth = 0
        var pictureDepth: Int?
        var payload = Data()
        var fileExtension: String?
        var highNibble: UInt8?
        var images: [(Data, String)] = []
        func hex(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: byte - 48
            case 65...70: byte - 55
            case 97...102: byte - 87
            default: nil
            }
        }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 123 { depth += 1; continue }
            if byte == 125 {
                if pictureDepth == depth {
                    guard highNibble == nil else { throw AppError.conversionFailed("Incomplete RTF picture data") }
                    if let ext = fileExtension, !payload.isEmpty { images.append((payload, ext)) }
                    pictureDepth = nil
                    payload = Data()
                    fileExtension = nil
                }
                depth -= 1
                guard depth >= 0 else { throw AppError.conversionFailed("Unbalanced RTF groups") }
                continue
            }
            if byte == 92 {
                guard index < bytes.count else { break }
                let start = index
                while index < bytes.count, (65...90).contains(bytes[index]) || (97...122).contains(bytes[index]) {
                    index += 1
                }
                if start == index {
                    // Escaped characters and control symbols cannot introduce groups or commands.
                    let symbol = bytes[index]
                    index += 1
                    if symbol == 39 { index = min(index + 2, bytes.count) }
                    continue
                }
                let command = String(decoding: bytes[start..<index], as: UTF8.self)
                let numberStart = index
                if index < bytes.count, bytes[index] == 45 { index += 1 }
                while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
                let number = Int(String(decoding: bytes[numberStart..<index], as: UTF8.self))
                if index < bytes.count, bytes[index] == 32 { index += 1 }
                if command == "bin" {
                    guard let length = number, length >= 0, length <= bytes.count - index else {
                        throw AppError.conversionFailed("Invalid RTF binary payload length")
                    }
                    if pictureDepth == depth { payload.append(contentsOf: bytes[index..<index + length]) }
                    index += length
                } else if command == "pict" {
                    guard pictureDepth == nil else { throw AppError.conversionFailed("Nested RTF pictures are not supported") }
                    pictureDepth = depth
                } else if pictureDepth == depth {
                    switch command {
                    case "pngblip": fileExtension = "png"
                    case "jpegblip": fileExtension = "jpg"
                    case "emfblip": fileExtension = "emf"
                    case "wmetafile": fileExtension = "wmf"
                    case "macpict": fileExtension = "pict"
                    case "dibitmap": fileExtension = "dib"
                    default: break
                    }
                }
                continue
            }
            if pictureDepth == depth {
                if let nibble = hex(byte) {
                    if let high = highNibble { payload.append(high * 16 + nibble); highNibble = nil }
                    else { highNibble = nibble }
                } else if ![9, 10, 13, 32].contains(byte) {
                    throw AppError.conversionFailed("Invalid RTF picture hex data")
                }
            }
        }
        guard depth == 0, pictureDepth == nil else { throw AppError.conversionFailed("Incomplete RTF document") }
        return images
    }
}
