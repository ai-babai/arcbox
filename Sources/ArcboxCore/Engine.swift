import Foundation

public struct ArchiveEngine: Sendable {
    public static let version = "0.2.3"
    public static let defaultLimit: Int64 = 20 * 1024 * 1024 * 1024
    public let executable: URL
    public init(executable: URL? = nil) throws {
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        let candidates = [
            executable,
            Bundle.main.resourceURL?.appendingPathComponent("7zz"),
            binary.deletingLastPathComponent().appendingPathComponent("../Resources/7zz").standardizedFileURL,
            binary.deletingLastPathComponent().appendingPathComponent("7zz"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("vendor/7zip/7zz"),
        ].compactMap { $0 }
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ArcboxError(
                "engine_missing", L("Не найден движок 7-Zip. Собери приложение командой ./scripts/build.sh."))
        }
        self.executable = found
    }

    public func list(_ archive: URL, password: String = "", token: OperationToken = .init()) throws -> ArchiveInfo {
        let set = try volumes(for: archive)
        let first = set.map { URL(fileURLWithPath: $0.firstPart) } ?? archive
        if let set, set.contentKind == "file" {
            let entry = ArchiveEntry(
                path: set.name, size: set.bytes, sizeKnown: true, packedSize: set.bytes, isDirectory: false,
                encrypted: false, modified: nil, crc: nil, isLink: false)
            return ArchiveInfo(
                path: first.path, archiveBytes: set.bytes, unpackedBytes: set.bytes, entries: [entry], volumes: set,
                isFileParts: true)
        }
        return try withReadableArchive(first, password: password, token: token, logicalName: set?.name) { readable in
            let content = try listPlain(readable, password: password, token: token)
            let size = try set?.bytes ?? Int64(archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            var result = ArchiveInfo(
                path: first.path, archiveBytes: size, unpackedBytes: content.unpackedBytes, entries: content.entries)
            result.volumes = set
            if set?.kind == "binary" {
                let probe = try run(["l", "-slt", "-sccUTF-8", "--", first.path], password: password, token: token)
                let types = probe.components(separatedBy: .newlines).filter { $0.hasPrefix("Type = ") }
                result.isFileParts = types.last?.lowercased() == "type = split"
            }
            return result
        }
    }

    private func listPlain(_ archive: URL, password: String, token: OperationToken) throws -> ArchiveInfo {
        try requireFile(archive)
        let output = try run(["l", "-slt", "-ba", "-sccUTF-8", "--", archive.path], password: password, token: token)
        var fallback = archive.deletingPathExtension().lastPathComponent
        if (3...5).contains(archive.pathExtension.count), archive.pathExtension.allSatisfy(\.isNumber) {
            // Stream codecs without stored names strip both the volume and compression extensions.
            fallback = (fallback as NSString).deletingPathExtension
        }
        let entries = try parseListing(output, fallbackName: fallback)
        let total = try sumSizes(entries)
        let bytes = (try archive.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        return ArchiveInfo(path: archive.path, archiveBytes: Int64(bytes), unpackedBytes: total, entries: entries)
    }

    public func test(_ archive: URL, password: String = "", token: OperationToken = .init()) throws -> OperationResult {
        let set = try volumes(for: archive)
        if let set { try verifyVolumes(set, token: token) }
        if let set, set.contentKind == "file" {
            return OperationResult(operation: "test", path: set.firstPart, files: 1, bytes: set.bytes)
        }
        let first = set.map { URL(fileURLWithPath: $0.firstPart) } ?? archive
        return try withReadableArchive(first, password: password, token: token, logicalName: set?.name) { readable in
            let info = try listPlain(readable, password: password, token: token)
            _ = try run(["t", "-bb0", "-bd", "--", readable.path], password: password, token: token)
            return OperationResult(
                operation: "test", path: archive.path, files: info.fileCount, bytes: info.unpackedBytes)
        }
    }

    /// Output is published only after successful extraction and validation. Existing paths are never replaced.
    public func extract(
        _ archive: URL, to destination: URL, entries selected: [String] = [], password: String = "",
        limit: Int64 = defaultLimit, token: OperationToken = .init()
    ) throws -> OperationResult {
        try requireNewDestination(destination)
        let set = try volumes(for: archive)
        if let set, set.contentKind == "file" {
            return try extractFileParts(set, to: destination, selected: selected, limit: limit, token: token)
        }
        if let set { try verifyVolumes(set, token: token) }
        let first = set.map { URL(fileURLWithPath: $0.firstPart) } ?? archive
        return try withReadableArchive(first, password: password, token: token, logicalName: set?.name) { readable in
            try extractPlain(
                readable, to: destination, entries: selected, password: password, limit: limit, token: token)
        }
    }

    private func extractPlain(
        _ archive: URL, to destination: URL, entries selected: [String], password: String, limit: Int64,
        token: OperationToken
    ) throws -> OperationResult {
        let archive = archive.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL
        try requireNewDestination(destination)
        let info = try listPlain(archive, password: password, token: token)
        try validateEntries(info.entries)
        let chosen = try select(info.entries, paths: selected)
        let bytes = try sumSizes(chosen)
        guard limit > 0, bytes <= limit else {
            throw ArcboxError(
                "size_limit", L("Распакованный размер превышает лимит %@ байт.", String(describing: (limit))))
        }
        try requireSpace(at: destination.deletingLastPathComponent(), bytes: bytes)
        let staging = try makeStaging(at: destination.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: staging) }
        var args = ["x", "-y", "-aos", "-bb0", "-bd", "-spd", "-o\(staging.path)"]
        let selectionFile = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Arcbox-selection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: selectionFile) }
        if !selected.isEmpty {
            try Data(selected.joined(separator: "\n").utf8).write(to: selectionFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: selectionFile.path)
            args += ["-i@\(selectionFile.path)", "-scsUTF-8"]
        }
        args += ["--", archive.path]
        _ = try run(args, password: password, token: token, writeRoot: staging, byteLimit: limit)
        try token.check()
        let actualBytes = try validateExtracted(staging, expected: chosen, limit: limit)
        try requireNewDestination(destination)
        try FileManager.default.moveItem(at: staging, to: destination)
        return OperationResult(
            operation: "extract", path: destination.path, files: chosen.filter { !$0.isDirectory }.count,
            bytes: actualBytes)
    }

    /// Compressed TARs expose their contents directly, rather than a single intermediary .tar file.
    private func withReadableArchive<T>(
        _ archive: URL, password: String, token: OperationToken, logicalName: String? = nil,
        operation: (URL) throws -> T
    ) throws -> T {
        let name = (logicalName ?? archive.lastPathComponent).lowercased()
        let compound = [".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tar.xz", ".txz", ".tar.zst", ".tzst"]
        guard compound.contains(where: { name.hasSuffix($0) }) else { return try operation(archive) }
        let outer = try listPlain(archive, password: password, token: token)
        guard outer.entries.count == 1, let entry = outer.entries.first, !entry.isDirectory else {
            throw ArcboxError("invalid_archive", L("Ожидался сжатый TAR-архив."))
        }
        let temporary = try makeStaging(at: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let container = temporary.appendingPathComponent("payload")
        _ = try extractPlain(
            archive, to: container, entries: [], password: password, limit: Self.defaultLimit, token: token)
        return try operation(container.appendingPathComponent(entry.path))
    }

    public func create(
        inputs: [URL], output: URL, format: String = "zip", level: Int = 5, password: String = "",
        partBytes: Int64? = nil, token: OperationToken = .init()
    ) throws -> OperationResult {
        if let partBytes {
            return try createVolumes(
                inputs: inputs, output: output, format: format, level: level, password: password, partBytes: partBytes,
                token: token)
        }
        let paths = try creationPaths(inputs, output: output, format: format, level: level, password: password)
        let parent = paths[0].deletingLastPathComponent()
        try requireNewDestination(output)
        let staging = try makeStaging(at: output.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: staging) }
        let temporaryArchive = staging.appendingPathComponent("archive.\(format)")
        var args = ["a", "-t\(format)", "-mx=\(level)", "-snl", "-spd", "-bb0", "-bd"]
        if !password.isEmpty {
            args += ["-p"]
            args += format == "7z" ? ["-mhe=on"] : ["-mem=AES256"]
        }
        args += ["--", temporaryArchive.path] + paths.map { "./" + $0.lastPathComponent }
        _ = try run(args, password: password, directory: parent, token: token)
        let info = try list(temporaryArchive, password: password, token: token)
        try token.check()
        try requireNewDestination(output)
        try FileManager.default.moveItem(at: temporaryArchive, to: output)
        return OperationResult(operation: "create", path: output.path, files: info.fileCount, bytes: info.archiveBytes)
    }

    private func creationPaths(_ inputs: [URL], output: URL, format: String, level: Int, password: String) throws
        -> [URL]
    {
        guard ["zip", "7z", "tar"].contains(format), (0...9).contains(level), !inputs.isEmpty else {
            throw ArcboxError("invalid_arguments", L("Нужны файлы, формат zip/7z/tar и уровень сжатия 0–9."))
        }
        if format == "tar" && !password.isEmpty {
            throw ArcboxError("invalid_arguments", L("TAR не поддерживает пароль. Выбери ZIP или 7z."))
        }
        let paths = inputs.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        let parent = paths[0].deletingLastPathComponent()
        guard paths.allSatisfy({ $0.deletingLastPathComponent() == parent }) else {
            throw ArcboxError("different_parents", L("Для одного архива выбери файлы из одной папки."))
        }
        for path in paths {
            try requireFile(path, allowDirectory: true)
            try validateName(path.lastPathComponent)
            if output.standardizedFileURL.path.hasPrefix(path.path + "/") {
                throw ArcboxError("invalid_destination", L("Сохрани архив вне папки, которую упаковываешь."))
            }
        }
        return paths
    }
}
