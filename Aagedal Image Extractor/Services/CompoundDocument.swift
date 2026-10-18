import Foundation

/// Read-only MS-CFB storage. Directory traversal excludes orphaned entries and embedded documents.
// Specification: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/
struct CompoundDocument {
    private let bytes: Data
    private let sectorSize: Int
    private let fat: [UInt32]
    private let miniFat: [UInt32]
    private let miniStream: Data
    private let entries: Data
    private let version: Int
    private let rootChildren: [Int]
    private static let end: UInt32 = 0xFFFFFFFE

    static func invalid(_ detail: String) -> AppError { .invalidArchive("Legacy Office: " + detail) }

    init(data: Data) throws {
        guard data.count >= 512, data.prefix(8) == Data([0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1]) else {
            throw Self.invalid("Expected an Office 97–2003 compound document. Older binary formats are not supported.")
        }
        let version = Int(data.le16(26))
        guard data.le16(28) == 0xFFFE, data.le16(32) == 6,
              (version == 3 && data.le16(30) == 9) || (version == 4 && data.le16(30) == 12),
              data.le32(56) == 4096 else { throw Self.invalid("Unsupported compound document header") }
        let size = 1 << Int(data.le16(30))
        guard data.count >= size, data.count % size == 0 else { throw Self.invalid("Truncated compound document") }
        let sectorCount = data.count / size - 1
        func sector(_ id: UInt32) throws -> Data {
            guard Int(id) < sectorCount else { throw Self.invalid("Invalid sector reference") }
            return data.subdata(in: (Int(id) + 1) * size..<(Int(id) + 2) * size)
        }
        var difat = (0..<109).map { data.le32(76 + $0 * 4) }.filter { $0 != 0xFFFFFFFF }
        var next = data.le32(68)
        var visited: Set<UInt32> = []
        let difatCount = Int(data.le32(72))
        guard difatCount <= sectorCount else { throw Self.invalid("Invalid DIFAT size") }
        for _ in 0..<difatCount {
            guard visited.insert(next).inserted else { throw Self.invalid("Cyclic DIFAT") }
            let block = try sector(next)
            difat += (0..<(size / 4 - 1)).map { block.le32($0 * 4) }.filter { $0 != 0xFFFFFFFF }
            next = block.le32(size - 4)
        }
        let fatCount = Int(data.le32(44))
        guard fatCount > 0, fatCount <= sectorCount, difat.count == fatCount,
              Set(difat).count == difat.count else { throw Self.invalid("Invalid FAT size") }
        var fat: [UInt32] = []
        for id in difat {
            let block = try sector(id)
            fat += (0..<size / 4).map { block.le32($0 * 4) }
        }
        func chain(_ start: UInt32, limit: Int? = nil) throws -> Data {
            var id = start
            var seen: Set<UInt32> = []
            var result = Data()
            while id != Self.end {
                guard Int(id) < fat.count, seen.insert(id).inserted, seen.count <= sectorCount else {
                    throw Self.invalid("Invalid or cyclic sector chain")
                }
                result.append(try sector(id))
                id = fat[Int(id)]
                if let limit, result.count >= limit { break }
            }
            if let limit, result.count < limit { throw Self.invalid("Truncated stream") }
            return result
        }
        let directory = try chain(data.le32(48))
        guard directory.count >= 128, directory[66] == 5 else { throw Self.invalid("Missing root storage") }
        func streamSize(_ offset: Int) throws -> Int {
            let low = UInt64(directory.le32(offset + 120))
            let high = version == 4 ? UInt64(directory.le32(offset + 124)) << 32 : 0
            guard low + high <= UInt64(data.count) else { throw Self.invalid("Stream exceeds document size") }
            return Int(low + high)
        }
        let rootSize = try streamSize(0)
        let mini = rootSize == 0 ? Data() : try chain(directory.le32(116), limit: rootSize).prefix(rootSize)
        let miniCount = Int(data.le32(64))
        guard miniCount <= sectorCount else { throw Self.invalid("Invalid mini FAT size") }
        let miniTable = miniCount == 0 ? Data() : try chain(data.le32(60), limit: miniCount * size)
        var children: [Int] = []
        var pending = [directory.le32(76)]
        var seen: Set<UInt32> = []
        while let id = pending.popLast() {
            if id == 0xFFFFFFFF { continue }
            guard Int(id) < directory.count / 128, seen.insert(id).inserted else {
                throw Self.invalid("Invalid directory tree")
            }
            let offset = Int(id) * 128
            children.append(Int(id))
            pending += [directory.le32(offset + 68), directory.le32(offset + 72)]
        }
        self.bytes = data
        self.sectorSize = size
        self.fat = fat
        self.miniFat = (0..<miniTable.count / 4).map { miniTable.le32($0 * 4) }
        self.miniStream = Data(mini)
        self.entries = directory
        self.version = version
        self.rootChildren = children
    }

    func stream(named name: String) throws -> Data? {
        var matches: [Int] = []
        for id in rootChildren {
            let offset = id * 128
            guard entries[offset + 66] == 2 else { continue }
            let length = Int(entries.le16(offset + 64))
            guard length >= 2, length <= 64, length % 2 == 0 else { throw Self.invalid("Invalid stream name") }
            let value = String(data: entries.subdata(in: offset..<offset + length - 2), encoding: .utf16LittleEndian)
            if value?.caseInsensitiveCompare(name) == .orderedSame { matches.append(offset) }
        }
        guard matches.count <= 1 else { throw Self.invalid("Duplicate stream name") }
        guard let offset = matches.first else { return nil }
        let length64 = UInt64(entries.le32(offset + 120)) + (version == 4 ? UInt64(entries.le32(offset + 124)) << 32 : 0)
        guard length64 <= UInt64(bytes.count) else { throw Self.invalid("Stream exceeds document size") }
        let length = Int(length64)
        if length == 0 { return Data() }
        let small = length < 4096
        let table = small ? miniFat : fat
        let blockSize = small ? 64 : sectorSize
        var id = entries.le32(offset + 116)
        var seen: Set<UInt32> = []
        var result = Data()
        while result.count < length {
            guard Int(id) < table.count, seen.insert(id).inserted else { throw Self.invalid("Invalid stream chain") }
            let source = small ? miniStream : bytes
            let start = small ? Int(id) * 64 : (Int(id) + 1) * sectorSize
            guard start <= source.count, blockSize <= source.count - start else { throw Self.invalid("Truncated stream sector") }
            result.append(source.subdata(in: start..<start + min(blockSize, length - result.count)))
            id = table[Int(id)]
        }
        guard id == Self.end else { throw Self.invalid("Stream chain exceeds declared size") }
        return result
    }
}

extension Data {
    // Callers validate ranges before reading; byte assembly avoids unaligned loads.
    func le16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func le32(_ offset: Int) -> UInt32 { UInt32(le16(offset)) | UInt32(le16(offset + 2)) << 16 }
}
