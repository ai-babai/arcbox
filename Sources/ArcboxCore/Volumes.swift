import Foundation
import CryptoKit

public struct VolumeSet: Codable, Sendable {
    public let firstPart: String
    public let name: String
    public let paths: [String]
    public let bytes: Int64
    public let kind: String
    public let hasManifest: Bool
    public var contentKind: String? = nil
    public var count: Int { paths.count }
}

extension ArchiveEngine {
    /// Resolve any selected volume to the start of its set. Discovery does not read archive payloads.
    public func volumes(for selected: URL) throws -> VolumeSet? {
        try requireFile(selected)
        let parent = selected.deletingLastPathComponent()
        var name = selected.lastPathComponent
        if name.hasSuffix(".arcbox-parts.json") { name = String(name.dropLast(".arcbox-parts.json".count)) + ".001" }
        let numeric = (name as NSString).pathExtension
        if (3...5).contains(numeric.count), numeric.allSatisfy({ $0.isASCII && $0.isNumber }) {
            let base = (name as NSString).deletingPathExtension
            let found = try numberedFiles(in: parent, pattern: "^" + NSRegularExpression.escapedPattern(for: base) + "\\.([0-9]{3,})$")
            try requireSequence(found, starting: 1, missingName: { base + String(format: ".%03d", $0) })
            return try volumeSet(found.map(\.1), name: base, kind: "binary", manifest: parent.appendingPathComponent(base + ".arcbox-parts.json"))
        }
        if let match = captures("^(.*)\\.part([0-9]+)\\.rar$", name) {
            let base = match[0], width = match[1].count
            let found = try numberedFiles(in: parent, pattern: "^" + NSRegularExpression.escapedPattern(for: base) + "\\.part([0-9]+)\\.rar$")
            try requireSequence(found, starting: 1, missingName: { base + ".part" + String(format: "%0*d", width, $0) + ".rar" })
            return try volumeSet(found.map(\.1), name: base + ".rar", kind: "rar")
        }
        let ext = (name as NSString).pathExtension.lowercased()
        for (kind, letter, firstExtension) in [("rar", "r", "rar"), ("zip", "z", "zip")] {
            let numbered = ext.count >= 3 && ext.hasPrefix(letter) && ext.dropFirst().allSatisfy(\.isNumber)
            guard ext == firstExtension || numbered else { continue }
            let base = (name as NSString).deletingPathExtension
            let parts = try numberedFiles(in: parent, pattern: "^" + NSRegularExpression.escapedPattern(for: base) + "\\." + letter + "([0-9]{2,})$")
            if parts.isEmpty && !numbered { continue }
            let first = parent.appendingPathComponent(base + "." + firstExtension)
            guard FileManager.default.fileExists(atPath: first.path) else { throw missingPart(first.lastPathComponent) }
            try requireSequence(parts, starting: kind == "rar" ? 0 : 1, missingName: { base + "." + letter + String(format: "%02d", $0) })
            let paths = kind == "rar" ? [first] + parts.map(\.1) : parts.map(\.1) + [first]
            var set = try volumeSet(paths, name: base + "." + firstExtension, kind: kind)
            // ZIP's directory is in the final .zip segment; 7-Zip must start from that file.
            if kind == "zip" { set = VolumeSet(firstPart: first.path, name: set.name, paths: set.paths, bytes: set.bytes, kind: kind, hasManifest: false) }
            return set
        }
        return nil
    }

    func verifyVolumes(_ set: VolumeSet, token: OperationToken) throws {
        guard set.hasManifest else { return }
        let manifest = try readManifest(URL(fileURLWithPath: set.firstPart).deletingLastPathComponent().appendingPathComponent(set.name + ".arcbox-parts.json"))
        guard manifest.version == 1, manifest.originalName == set.name, manifest.parts.map(\.name) == set.paths.map({ ($0 as NSString).lastPathComponent }) else {
            throw ArcboxError("invalid_manifest", L("Файл проверки изменился. Открой набор частей заново."))
        }
        var whole = SHA256()
        for (index, path) in set.paths.enumerated() {
            let input = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? input.close() }
            var hash = SHA256(), size: Int64 = 0
            while true {
                try token.check()
                let chunk = try input.read(upToCount: 1024 * 1024) ?? Data()
                if chunk.isEmpty { break }
                hash.update(data: chunk); whole.update(data: chunk); size += Int64(chunk.count)
            }
            guard manifest.parts[index].sha256 == digest(hash.finalize()), manifest.parts[index].bytes == size else {
                throw ArcboxError("part_corrupt", L("Повреждена часть %@. Замени её и повтори распаковку.", String(describing: ((path as NSString).lastPathComponent))))
            }
        }
        guard manifest.sha256 == digest(whole.finalize()), manifest.bytes == set.bytes else { throw ArcboxError("checksum_mismatch", L("Контрольная сумма набора частей не совпала.")) }
    }

    func createVolumes(inputs: [URL], output: URL, format: String, level: Int, password: String, partBytes: Int64, token: OperationToken) throws -> OperationResult {
        guard partBytes > 0 else { throw ArcboxError("invalid_arguments", L("Размер части должен быть больше нуля.")) }
        try requireNewDestination(output)
        let staging = try makeStaging(at: output.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: staging) }
        let source: URL
        let files: Int
        if format == "parts" {
            guard inputs.count == 1, password.isEmpty else { throw ArcboxError("invalid_arguments", L("Для частей исходного файла выбери один файл без пароля.")) }
            source = inputs[0]; files = 1
        } else {
            var name = output.lastPathComponent
            if name.hasSuffix(".parts") { name = String(name.dropLast(6)) }
            if !(name as NSString).pathExtension.lowercased().elementsEqual(format) { name += "." + format }
            source = staging.appendingPathComponent(name)
            let created = try create(inputs: inputs, output: source, format: format, level: level, password: password, token: token)
            files = created.files
        }
        let partFolder = staging.appendingPathComponent("volumes")
        let result = try split(source, to: partFolder, partBytes: partBytes, token: token)
        let manifestURL = partFolder.appendingPathComponent(source.lastPathComponent + ".arcbox-parts.json")
        var manifest = try readManifest(manifestURL)
        manifest.contentKind = format == "parts" ? "file" : "archive"
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try token.check(); try requireNewDestination(output)
        try FileManager.default.moveItem(at: partFolder, to: output)
        return OperationResult(operation: "create", path: output.path, files: files, bytes: result.bytes, firstPart: output.appendingPathComponent(source.lastPathComponent + ".001").path, parts: result.parts)
    }

    private func volumeSet(_ paths: [URL], name: String, kind: String, manifest manifestURL: URL? = nil) throws -> VolumeSet {
        guard let first = paths.first, paths.count <= 10_000 else { throw ArcboxError("missing_parts", L("Не найден первый том или частей больше 10 000.")) }
        var total: Int64 = 0
        for path in paths {
            let values = try path.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ArcboxError("invalid_part", L("Часть %@ должна быть обычным файлом.", String(describing: (path.lastPathComponent)))) }
            let (sum, overflow) = total.addingReportingOverflow(Int64(values.fileSize ?? 0))
            guard !overflow else { throw ArcboxError("size_limit", L("Набор частей слишком велик.")) }; total = sum
        }
        let hasManifest = manifestURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        var contentKind: String?
        if let manifestURL, hasManifest {
            let manifest = try readManifest(manifestURL)
            let actual = paths.map(\.lastPathComponent)
            guard manifest.version == 1, manifest.originalName == name else { throw ArcboxError("invalid_manifest", L("Файл проверки относится к другому набору.")) }
            guard manifest.contentKind == nil || ["file", "archive"].contains(manifest.contentKind!) else { throw ArcboxError("invalid_manifest", L("Неизвестный тип содержимого набора.")) }
            contentKind = manifest.contentKind
            for expected in manifest.parts where !actual.contains(expected.name) { throw missingPart(expected.name) }
            guard manifest.parts.map(\.name) == actual else { throw ArcboxError("invalid_manifest", L("Порядок частей не совпадает с файлом проверки.")) }
            for (index, path) in paths.enumerated() {
                let size = Int64((try path.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
                guard size == manifest.parts[index].bytes else { throw ArcboxError("part_corrupt", L("Размер части %@ не совпал. Возможно, загрузка ещё не завершена.", String(describing: (path.lastPathComponent)))) }
            }
        }
        return VolumeSet(firstPart: first.path, name: name, paths: paths.map(\.path), bytes: total, kind: kind, hasManifest: hasManifest, contentKind: contentKind)
    }
    func extractFileParts(_ set: VolumeSet, to destination: URL, selected: [String], limit: Int64, token: OperationToken) throws -> OperationResult {
        try validateName(set.name)
        guard selected.allSatisfy({ $0 == set.name }) else { throw ArcboxError("entry_missing", L("В наборе есть только файл %@.", String(describing: (set.name)))) }
        guard limit > 0, set.bytes <= limit else { throw ArcboxError("size_limit", L("Размер файла превышает лимит распаковки.")) }
        try requireSpace(at: destination.deletingLastPathComponent(), bytes: set.bytes)
        let staging = try makeStaging(at: destination.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: staging) }
        _ = try join(URL(fileURLWithPath: set.firstPart), output: staging.appendingPathComponent(set.name), token: token)
        try token.check(); try requireNewDestination(destination)
        try FileManager.default.moveItem(at: staging, to: destination)
        return OperationResult(operation: "extract", path: destination.path, files: 1, bytes: set.bytes)
    }
    private func numberedFiles(in parent: URL, pattern: String) throws -> [(Int, URL)] {
        try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).compactMap { url in
            guard let value = captures(pattern, url.lastPathComponent)?.first, let number = Int(value) else { return nil }
            return (number, url)
        }.sorted { $0.0 < $1.0 }
    }
    private func requireSequence(_ files: [(Int, URL)], starting: Int, missingName: (Int) -> String) throws {
        if files.isEmpty { throw missingPart(missingName(starting)) }
        for (offset, file) in files.enumerated() {
            guard file.0 == offset + starting else { throw missingPart(missingName(offset + starting)) }
        }
    }
    private func readManifest(_ url: URL) throws -> PartsManifest {
        guard ((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max) <= 4 * 1024 * 1024,
              let manifest = try? JSONDecoder().decode(PartsManifest.self, from: Data(contentsOf: url)) else { throw ArcboxError("invalid_manifest", L("Не удалось прочитать файл проверки частей.")) }
        return manifest
    }
    private func missingPart(_ name: String) -> ArcboxError { ArcboxError("missing_parts", L("Не хватает части %@. Положи все части в одну папку и нажми «Повторить».", String(describing: (name)))) }
    private func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
    private func digest<D: Sequence>(_ value: D) -> String where D.Element == UInt8 { value.map { String(format: "%02x", $0) }.joined() }
}
