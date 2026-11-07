import Foundation
import CryptoKit

public struct PartsResult: Codable, Sendable {
    public let operation: String
    public let path: String
    public let parts: Int
    public let bytes: Int64
    public let verified: Bool
    public let sha256: String
}

struct PartRecord: Codable {
    let name: String
    let bytes: Int64
    let sha256: String
}
struct PartsManifest: Codable {
    let version: Int
    let originalName: String
    let bytes: Int64
    let partBytes: Int64
    let sha256: String
    let parts: [PartRecord]
    var contentKind: String? = nil
}

extension ArchiveEngine {
    /// Binary splitting works with any file. Keep the adjacent manifest for end-to-end verification.
    public func split(_ file: URL, to destination: URL, partBytes: Int64, token: OperationToken = .init()) throws -> PartsResult {
        try requireFile(file)
        try validateName(file.lastPathComponent)
        try requireNewDestination(destination)
        guard partBytes > 0 else { throw ArcboxError("invalid_arguments", L("Размер части должен быть больше нуля.")) }
        let size = Int64((try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
        let count = size == 0 ? 1 : (size - 1) / partBytes + 1
        guard count <= 10_000 else { throw ArcboxError("too_many_parts", L("Получится больше 10 000 частей. Увеличь размер части.")) }
        try requireSpace(at: destination.deletingLastPathComponent(), bytes: size)
        let staging = try makeStaging(at: destination.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: staging) }
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var wholeHash = SHA256(), records: [PartRecord] = [], total: Int64 = 0
        for index in 1...Int(count) {
            try token.check()
            let name = file.lastPathComponent + String(format: ".%03d", index)
            let target = staging.appendingPathComponent(name)
            guard FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw ArcboxError("io_error", L("Не удалось создать часть.")) }
            let output = try FileHandle(forWritingTo: target)
            defer { try? output.close() }
            var partHash = SHA256(), written: Int64 = 0
            while written < partBytes {
                try token.check()
                let data = try input.read(upToCount: Int(min(partBytes - written, 1024 * 1024))) ?? Data()
                if data.isEmpty { break }
                try output.write(contentsOf: data)
                partHash.update(data: data); wholeHash.update(data: data)
                written += Int64(data.count); total += Int64(data.count)
            }
            try output.synchronize()
            records.append(PartRecord(name: name, bytes: written, sha256: hex(partHash.finalize())))
        }
        guard total == size, (try input.read(upToCount: 1) ?? Data()).isEmpty else {
            throw ArcboxError("source_changed", L("Исходный файл изменился во время разбиения. Повтори операцию."))
        }
        let digest = hex(wholeHash.finalize())
        let manifest = PartsManifest(version: 1, originalName: file.lastPathComponent, bytes: size, partBytes: partBytes, sha256: digest, parts: records)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: staging.appendingPathComponent(file.lastPathComponent + ".arcbox-parts.json"))
        try token.check(); try requireNewDestination(destination)
        try FileManager.default.moveItem(at: staging, to: destination)
        return PartsResult(operation: "split", path: destination.path, parts: records.count, bytes: size, verified: true, sha256: digest)
    }

    /// Standard .001/.002 chunks are accepted; a sibling manifest makes missing final parts detectable.
    public func join(_ firstPart: URL, output: URL, token: OperationToken = .init()) throws -> PartsResult {
        guard firstPart.lastPathComponent.hasSuffix(".001") else {
            throw ArcboxError("invalid_arguments", L("Выбери первую часть .001. Для многотомного RAR открой первый .part1.rar как архив."))
        }
        try requireFile(firstPart); try requireNewDestination(output)
        let parent = firstPart.deletingLastPathComponent()
        let name = firstPart.deletingPathExtension().lastPathComponent
        let partURLs = try collectParts(parent: parent, name: name)
        let manifestURL = parent.appendingPathComponent(name + ".arcbox-parts.json")
        var manifest: PartsManifest?
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
            guard data.count <= 4 * 1024 * 1024 else { throw ArcboxError("invalid_manifest", L("Слишком большой файл проверки частей.")) }
            guard let decoded = try? JSONDecoder().decode(PartsManifest.self, from: data), decoded.version == 1,
                  decoded.originalName == name, decoded.parts.map(\.name) == partURLs.map(\.lastPathComponent) else {
                throw ArcboxError("missing_parts", L("Набор частей не совпадает с файлом проверки. Возможно, часть потеряна или переименована."))
            }
            manifest = decoded
        }
        var size: Int64 = 0
        for part in partURLs {
            let values = try part.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ArcboxError("invalid_part", L("Части должны быть обычными файлами.")) }
            let (sum, overflow) = size.addingReportingOverflow(Int64(values.fileSize ?? 0))
            guard !overflow else { throw ArcboxError("size_limit", L("Слишком большой размер частей.")) }; size = sum
        }
        try requireSpace(at: output.deletingLastPathComponent(), bytes: size)
        let staging = try makeStaging(at: output.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: staging) }
        let assembled = staging.appendingPathComponent("assembled")
        guard FileManager.default.createFile(atPath: assembled.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw ArcboxError("io_error", L("Не удалось создать файл.")) }
        let target = try FileHandle(forWritingTo: assembled)
        defer { try? target.close() }
        var wholeHash = SHA256(), total: Int64 = 0
        for (index, part) in partURLs.enumerated() {
            try token.check()
            let input = try FileHandle(forReadingFrom: part)
            defer { try? input.close() }
            var partHash = SHA256(), partSize: Int64 = 0
            while true {
                try token.check()
                let data = try input.read(upToCount: 1024 * 1024) ?? Data()
                if data.isEmpty { break }
                try target.write(contentsOf: data)
                partHash.update(data: data); wholeHash.update(data: data)
                partSize += Int64(data.count); total += Int64(data.count)
            }
            if let expected = manifest?.parts[index], (expected.bytes != partSize || expected.sha256 != hex(partHash.finalize())) {
                throw ArcboxError("part_corrupt", L("Часть %@ повреждена. Сборка остановлена.", String(describing: (part.lastPathComponent))))
            }
        }
        let digest = hex(wholeHash.finalize())
        guard total == size else { throw ArcboxError("source_changed", L("Части изменились во время сборки.")) }
        if let manifest, (manifest.bytes != total || manifest.sha256 != digest) {
            throw ArcboxError("checksum_mismatch", L("Контрольная сумма собранного файла не совпала с оригиналом."))
        }
        try target.synchronize(); try target.close()
        // Joined content has the same trust status as extracted content.
        let quarantine = "0081;\(String(Int(Date().timeIntervalSince1970), radix: 16));Arcbox;"
        _ = quarantine.withCString { setxattr(assembled.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
        try token.check(); try requireNewDestination(output)
        try FileManager.default.moveItem(at: assembled, to: output)
        return PartsResult(operation: "join", path: output.path, parts: partURLs.count, bytes: total, verified: manifest != nil, sha256: digest)
    }

    private func collectParts(parent: URL, name: String) throws -> [URL] {
        let prefix = name + "."
        let found = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).compactMap { url -> (Int, URL)? in
            guard url.lastPathComponent.hasPrefix(prefix) else { return nil }
            let suffix = String(url.lastPathComponent.dropFirst(prefix.count))
            guard suffix.count >= 3, suffix.allSatisfy({ $0.isASCII && $0.isNumber }), let index = Int(suffix) else { return nil }
            return (index, url)
        }.sorted { $0.0 < $1.0 }
        guard !found.isEmpty, found.count <= 10_000 else { throw ArcboxError("missing_parts", L("Части не найдены или их больше 10 000.")) }
        for (offset, item) in found.enumerated() {
            guard item.0 == offset + 1, item.1.lastPathComponent == name + String(format: ".%03d", offset + 1) else {
                throw ArcboxError("missing_parts", L("Нарушена последовательность частей. Ожидалась часть %@.", String(describing: (String(format: "%03d", offset + 1)))))
            }
        }
        return found.map { $0.1 }
    }
}

private func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 { digest.map { String(format: "%02x", $0) }.joined() }
