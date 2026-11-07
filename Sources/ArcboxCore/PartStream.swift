import CryptoKit
import Foundation

extension ArchiveEngine {
    /// Bounded memory for split, join and manifest verification; hash exactly the bytes read.
    func streamPart(
        _ input: FileHandle, to output: FileHandle? = nil, name: String, limit: Int64 = .max,
        whole: inout SHA256, token: OperationToken
    ) throws -> PartRecord {
        var hash = SHA256()
        var bytes: Int64 = 0
        while bytes < limit {
            try token.check()
            let data = try input.read(upToCount: Int(min(limit - bytes, 1024 * 1024))) ?? Data()
            if data.isEmpty { break }
            try output?.write(contentsOf: data)
            hash.update(data: data)
            whole.update(data: data)
            bytes += Int64(data.count)
        }
        return PartRecord(name: name, bytes: bytes, sha256: digest(hash.finalize()))
    }
}

func digest<D: Sequence>(_ value: D) -> String where D.Element == UInt8 {
    value.map { String(format: "%02x", $0) }.joined()
}
