import Foundation
import ZIPFoundation

final class ZIPArchiveReader {
    static let maximumEntryCount = 10_000
    static let maximumDeclaredTotalSize: UInt64 = 512 * 1024 * 1024
    static let maximumReadBytes = 64 * 1024 * 1024

    private let archive: Archive
    private(set) var paths: [String]
    private var cumulativeReadBytes = 0

    init(url: URL) throws {
        archive = try Archive(url: url, accessMode: .read)
        var collectedPaths: [String] = []
        var declaredTotalSize: UInt64 = 0
        for entry in archive {
            guard collectedPaths.count < Self.maximumEntryCount else {
                throw FreeNoteError.invalidState("压缩包条目数量超过安全上限。")
            }
            guard Self.isSafeArchivePath(entry.path) else {
                throw FreeNoteError.invalidState("压缩包包含不安全路径：\(entry.path)")
            }
            if declaredTotalSize <= UInt64.max - entry.uncompressedSize {
                declaredTotalSize += entry.uncompressedSize
            } else {
                throw FreeNoteError.invalidState("压缩包声明大小无效。")
            }
            guard declaredTotalSize <= Self.maximumDeclaredTotalSize else {
                throw FreeNoteError.invalidState("压缩包展开后大小超过安全上限。")
            }
            collectedPaths.append(entry.path)
        }
        paths = collectedPaths
    }

    func contains(_ path: String) -> Bool {
        guard Self.isSafeArchivePath(path) else {
            return false
        }
        return archive[path]?.type == .file
    }

    func read(path: String, maximumBytes: Int) -> Data? {
        guard maximumBytes > 0,
              maximumBytes <= Self.maximumReadBytes,
              cumulativeReadBytes <= Self.maximumReadBytes - maximumBytes,
              Self.isSafeArchivePath(path),
              let entry = archive[path],
              entry.type == .file,
              entry.uncompressedSize <= UInt64(maximumBytes) else {
            return nil
        }

        var data = Data()
        data.reserveCapacity(Int(entry.uncompressedSize))
        var limitExceeded = false
        do {
            _ = try archive.extract(entry, skipCRC32: true) { chunk in
                guard chunk.count <= maximumBytes - data.count else {
                    limitExceeded = true
                    throw ZIPArchiveReaderError.limitExceeded
                }
                data.append(chunk)
            }
        } catch {
            return nil
        }
        guard !limitExceeded else {
            return nil
        }
        cumulativeReadBytes += data.count
        return data
    }

    static func isSafeArchivePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\0"),
              !path.contains("\\"),
              !path.contains(":") else {
            return false
        }
        let decoded = path.removingPercentEncoding ?? path
        guard decoded == path || isSafeArchivePath(decoded) else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return !components.contains { $0 == ".." || $0 == "." }
    }
}

private enum ZIPArchiveReaderError: Error {
    case limitExceeded
}
