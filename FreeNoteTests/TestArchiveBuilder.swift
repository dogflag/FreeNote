import Foundation

enum TestArchiveBuilder {
    static func createArchive(at url: URL, entries: [String: String]) throws {
        let archiveEntries: [(path: String, data: Data)] = entries.map { entry in
            (path: entry.key, data: Data(entry.value.utf8))
        }
        let archiveData = try buildStoredZIP(entries: archiveEntries)
        try archiveData.write(to: url, options: [.atomic])
    }

    private struct Entry {
        let path: String
        let data: Data
    }

    private static func buildStoredZIP(entries: [(path: String, data: Data)]) throws -> Data {
        guard entries.count <= Int(UInt16.max) else {
            throw TestArchiveError.tooManyEntries
        }

        var localData = Data()
        var centralData = Data()
        for entry in entries {
            let pathData = Data(entry.path.utf8)
            guard pathData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  localData.count <= Int(UInt32.max) else {
                throw TestArchiveError.entryTooLarge
            }
            let crc = crc32(entry.data)
            let localOffset = UInt32(localData.count)

            localData.appendUInt32(0x04034b50)
            localData.appendUInt16(20)
            localData.appendUInt16(0)
            localData.appendUInt16(0)
            localData.appendUInt16(0)
            localData.appendUInt16(0)
            localData.appendUInt32(crc)
            localData.appendUInt32(UInt32(entry.data.count))
            localData.appendUInt32(UInt32(entry.data.count))
            localData.appendUInt16(UInt16(pathData.count))
            localData.appendUInt16(0)
            localData.append(pathData)
            localData.append(entry.data)

            centralData.appendUInt32(0x02014b50)
            centralData.appendUInt16(20)
            centralData.appendUInt16(20)
            centralData.appendUInt16(0)
            centralData.appendUInt16(0)
            centralData.appendUInt16(0)
            centralData.appendUInt16(0)
            centralData.appendUInt32(crc)
            centralData.appendUInt32(UInt32(entry.data.count))
            centralData.appendUInt32(UInt32(entry.data.count))
            centralData.appendUInt16(UInt16(pathData.count))
            centralData.appendUInt16(0)
            centralData.appendUInt16(0)
            centralData.appendUInt16(0)
            centralData.appendUInt16(0)
            centralData.appendUInt32(0)
            centralData.appendUInt32(localOffset)
            centralData.append(pathData)
        }

        guard localData.count <= Int(UInt32.max),
              centralData.count <= Int(UInt32.max) else {
            throw TestArchiveError.archiveTooLarge
        }

        var result = localData
        result.append(centralData)
        result.appendUInt32(0x06054b50)
        result.appendUInt16(0)
        result.appendUInt16(0)
        result.appendUInt16(UInt16(entries.count))
        result.appendUInt16(UInt16(entries.count))
        result.appendUInt32(UInt32(centralData.count))
        result.appendUInt32(UInt32(localData.count))
        result.appendUInt16(0)
        return result
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) == 1 {
                    crc = (crc >> 1) ^ 0xedb88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xffffffff
    }
}

private enum TestArchiveError: Error {
    case tooManyEntries
    case entryTooLarge
    case archiveTooLarge
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
