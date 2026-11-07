import Foundation

public struct ArchiveEngine: Sendable {
    public static let version = "0.2.1"
    public static let defaultLimit: Int64 = 20 * 1024 * 1024 * 1024
    public let executable: URL
    public init(executable: URL? = nil) throws {
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        let candidates = [
            executable,
            Bundle.main.resourceURL?.appendingPathComponent("7zz"),
            binary.deletingLastPathComponent().appendingPathComponent("../Resources/7zz").standardizedFileURL,
            binary.deletingLastPathComponent().appendingPathComponent("7zz"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("vendor/7zip/7zz")
        ].compactMap { $0 }
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ArcboxError("engine_missing", L("Не найден движок 7-Zip. Собери приложение командой ./scripts/build.sh."))
        }
        self.executable = found
    }

    public func list(_ archive: URL, password: String = "", token: OperationToken = .init()) throws -> ArchiveInfo {
        let set = try volumes(for: archive)
        let first = set.map { URL(fileURLWithPath: $0.firstPart) } ?? archive
        if let set, set.contentKind == "file" {
            let entry = ArchiveEntry(path: set.name, size: set.bytes, sizeKnown: true, packedSize: set.bytes, isDirectory: false, encrypted: false, modified: nil, crc: nil, isLink: false)
            return ArchiveInfo(path: first.path, archiveBytes: set.bytes, unpackedBytes: set.bytes, entries: [entry], volumes: set, isFileParts: true)
        }
        return try withReadableArchive(first, password: password, token: token, logicalName: set?.name) { readable in
            let content = try listPlain(readable, password: password, token: token)
            let size = try set?.bytes ?? Int64(archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            var result = ArchiveInfo(path: first.path, archiveBytes: size, unpackedBytes: content.unpackedBytes, entries: content.entries)
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
        if let set, set.contentKind == "file" { return OperationResult(operation: "test", path: set.firstPart, files: 1, bytes: set.bytes) }
        let first = set.map { URL(fileURLWithPath: $0.firstPart) } ?? archive
        return try withReadableArchive(first, password: password, token: token, logicalName: set?.name) { readable in
            let info = try listPlain(readable, password: password, token: token)
            _ = try run(["t", "-bb0", "-bd", "--", readable.path], password: password, token: token)
            return OperationResult(operation: "test", path: archive.path, files: info.fileCount, bytes: info.unpackedBytes)
        }
    }

    /// Output is published only after successful extraction and validation. Existing paths are never replaced.
    public func extract(_ archive: URL, to destination: URL, entries selected: [String] = [], password: String = "", limit: Int64 = defaultLimit, token: OperationToken = .init()) throws -> OperationResult {
        try requireNewDestination(destination)
        let set = try volumes(for: archive)
        if let set, set.contentKind == "file" { return try extractFileParts(set, to: destination, selected: selected, limit: limit, token: token) }
        if let set { try verifyVolumes(set, token: token) }
        let first = set.map { URL(fileURLWithPath: $0.firstPart) } ?? archive
        return try withReadableArchive(first, password: password, token: token, logicalName: set?.name) { readable in
            try extractPlain(readable, to: destination, entries: selected, password: password, limit: limit, token: token)
        }
    }

    private func extractPlain(_ archive: URL, to destination: URL, entries selected: [String], password: String, limit: Int64, token: OperationToken) throws -> OperationResult {
        let archive = archive.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL
        try requireNewDestination(destination)
        let info = try listPlain(archive, password: password, token: token)
        try validateEntries(info.entries)
        let chosen = try select(info.entries, paths: selected)
        let bytes = try sumSizes(chosen)
        guard limit > 0, bytes <= limit else { throw ArcboxError("size_limit", L("Распакованный размер превышает лимит %@ байт.", String(describing: (limit)))) }
        try requireSpace(at: destination.deletingLastPathComponent(), bytes: bytes)
        let staging = try makeStaging(at: destination.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: staging) }
        var args = ["x", "-y", "-aos", "-bb0", "-bd", "-spd", "-o\(staging.path)"]
        let selectionFile = FileManager.default.temporaryDirectory.appendingPathComponent("Arcbox-selection-\(UUID().uuidString)")
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
        return OperationResult(operation: "extract", path: destination.path, files: chosen.filter { !$0.isDirectory }.count, bytes: actualBytes)
    }

    /// Compressed TARs expose their contents directly, rather than a single intermediary .tar file.
    private func withReadableArchive<T>(_ archive: URL, password: String, token: OperationToken, logicalName: String? = nil, operation: (URL) throws -> T) throws -> T {
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
        _ = try extractPlain(archive, to: container, entries: [], password: password, limit: Self.defaultLimit, token: token)
        return try operation(container.appendingPathComponent(entry.path))
    }

    public func create(inputs: [URL], output: URL, format: String = "zip", level: Int = 5, password: String = "", partBytes: Int64? = nil, token: OperationToken = .init()) throws -> OperationResult {
        if let partBytes { return try createVolumes(inputs: inputs, output: output, format: format, level: level, password: password, partBytes: partBytes, token: token) }
        guard ["zip", "7z", "tar"].contains(format), (0...9).contains(level), !inputs.isEmpty else {
            throw ArcboxError("invalid_arguments", L("Нужны файлы, формат zip/7z/tar и уровень сжатия 0–9."))
        }
        if format == "tar" && !password.isEmpty { throw ArcboxError("invalid_arguments", L("TAR не поддерживает пароль. Выбери ZIP или 7z.")) }
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

    private func run(_ arguments: [String], password: String, directory: URL? = nil, token: OperationToken, writeRoot: URL? = nil, byteLimit: Int64? = nil) throws -> String {
        try token.check()
        guard !password.contains("\n"), !password.contains("\r"), !password.contains("\0") else {
            throw ArcboxError("invalid_password", L("Пароль не должен содержать перевод строки или нулевой символ."))
        }
        let child = Process()
        // macOS Seatbelt confines extraction writes, including writes through archive symlinks.
        if let root = writeRoot {
            guard let resolved = realpath(root.path, nil) else { throw ArcboxError("invalid_destination", L("Не удалось разрешить путь папки.")) }
            let canonical = String(cString: resolved)
            free(resolved)
            let literal = canonical.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let profile = "(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (subpath \"\(literal)\") (literal \"/dev/null\"))"
            child.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            child.arguments = ["-p", profile, executable.path] + arguments
        } else {
            child.executableURL = executable; child.arguments = arguments
        }
        child.currentDirectoryURL = directory
        child.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8", "HOME": FileManager.default.homeDirectoryForCurrentUser.path]
        let stdout = Pipe(), stdin = Pipe()
        child.standardOutput = stdout; child.standardError = stdout; child.standardInput = stdin
        try token.launch(child)
        defer { token.clear() }
        stdin.fileHandleForWriting.write(Data((password + "\n" + password + "\n").utf8))
        try? stdin.fileHandleForWriting.close()
        let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        let started = Date()
        watchdog.schedule(deadline: .now() + 1, repeating: 1)
        watchdog.setEventHandler {
            if Date().timeIntervalSince(started) > 1800 { token.cancel() }
            if let root = writeRoot, let limit = byteLimit,
               let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
                var size: Int64 = 0
                for case let url as URL in walker {
                    size += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    if size > limit { token.cancel(); break }
                }
            }
        }
        watchdog.resume()
        defer { watchdog.cancel() }
        var data = Data()
        while true {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > 64 * 1024 * 1024 { token.cancel() }
        }
        child.waitUntilExit()
        try token.check()
        let output = String(decoding: data, as: UTF8.self)
        guard child.terminationStatus == 0 else {
            let lower = output.lowercased()
            if lower.contains("missing volume") || lower.contains("cannot find volume") {
                throw ArcboxError("missing_parts", L("Не хватает тома архива. Положи все части рядом и повтори операцию."))
            }
            if lower.contains("password") || lower.contains("encrypted") {
                throw ArcboxError("password_required", L("Нужен правильный пароль для этого архива."))
            }
            let detail = output.components(separatedBy: .newlines).filter { $0.contains("ERROR") || $0.contains("Error") || $0.contains("Denied") }.prefix(4).joined(separator: "\n")
            throw ArcboxError("engine_error", detail.isEmpty ? L("Не удалось обработать архив (код %@). Возможно, он повреждён или формат не поддерживается.", String(describing: (child.terminationStatus))) : detail)
        }
        return output
    }

    private func parseListing(_ text: String, fallbackName: String) throws -> [ArchiveEntry] {
        var records: [[String: String]] = [], current: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            if line.isEmpty || line == "Enter password:" {
                if !current.isEmpty { records.append(current); current = [:] }
                continue
            }
            guard let range = line.range(of: " = ") else { throw ArcboxError("ambiguous_name", L("Неоднозначное имя файла в архиве. Операция остановлена.")) }
            let key = String(line[..<range.lowerBound]), value = String(line[range.upperBound...])
            guard current[key] == nil else { throw ArcboxError("ambiguous_name", L("Неоднозначные метаданные архива.")) }
            current[key] = value
        }
        if !current.isEmpty { records.append(current) }
        return try records.map { record in
            let path = record["Path"] ?? fallbackName
            let sizeValue = record["Size"].flatMap(Int64.init)
            let size = sizeValue ?? 0
            guard size >= 0, record["Size"] != nil || record["Folder"] == "+" else {
                throw ArcboxError("invalid_archive", L("Не удалось прочитать список файлов."))
            }
            let attrs = record["Attributes"] ?? ""
            return ArchiveEntry(path: path, size: size, sizeKnown: sizeValue != nil, packedSize: record["Packed Size"].flatMap(Int64.init), isDirectory: record["Folder"] == "+" || attrs.hasPrefix("D") || attrs.contains(" dr"), encrypted: record["Encrypted"] == "+", modified: record["Modified"], crc: record["CRC"], isLink: !(record["Symbolic Link"] ?? "").isEmpty || !(record["Hard Link"] ?? "").isEmpty || attrs.contains(" lr") || attrs.hasPrefix("l"))
        }
    }

    func validateName(_ name: String) throws {
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !name.isEmpty, !normalized.hasPrefix("/"), !name.contains(":"),
              !parts.contains(".."), !parts.contains("."),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ArcboxError("unsafe_path", L("Небезопасный путь в архиве: %@", String(describing: (name))))
        }
    }
    private func validateEntries(_ entries: [ArchiveEntry]) throws {
        var names = Set<String>()
        for entry in entries {
            try validateName(entry.path)
            guard !entry.isLink else { throw ArcboxError("unsafe_link", L("Архив содержит ссылку: %@. Распаковка ссылок пока отключена.", String(describing: (entry.path)))) }
            let normalized = entry.path.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard names.insert(normalized).inserted else { throw ArcboxError("path_collision", L("Имена файлов конфликтуют на macOS: %@", String(describing: (entry.path)))) }
        }
    }
    private func select(_ entries: [ArchiveEntry], paths: [String]) throws -> [ArchiveEntry] {
        if paths.isEmpty { return entries }
        for path in paths {
            guard entries.contains(where: { $0.path == path }) else { throw ArcboxError("entry_missing", L("В архиве нет файла %@", String(describing: (path)))) }
        }
        return entries.filter { entry in paths.contains { entry.path == $0 || entry.path.hasPrefix($0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/") } }
    }
    private func sumSizes(_ entries: [ArchiveEntry]) throws -> Int64 {
        var size: Int64 = 0
        for entry in entries {
            let (sum, overflow) = size.addingReportingOverflow(entry.size)
            guard !overflow else { throw ArcboxError("size_limit", L("Размер архива слишком велик.")) }
            size = sum
        }
        return size
    }
    func requireFile(_ url: URL, allowDirectory: Bool = false) throws {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), allowDirectory || !directory.boolValue else {
            throw ArcboxError("file_missing", L("Файл не найден: %@", String(describing: (url.path))))
        }
    }
    func requireNewDestination(_ url: URL) throws {
        if (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil {
            throw ArcboxError("destination_exists", L("Этот путь уже существует. Выбери новое имя: %@", String(describing: (url.lastPathComponent))))
        }
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &dir), dir.boolValue else {
            throw ArcboxError("invalid_destination", L("Родительская папка должна существовать."))
        }
    }
    func requireSpace(at url: URL, bytes: Int64) throws {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available - 512 * 1024 * 1024 < bytes {
            throw ArcboxError("disk_full", L("Недостаточно свободного места для распаковки."))
        }
    }
    func makeStaging(at parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(".arcbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }
    private func validateExtracted(_ root: URL, expected: [ArchiveEntry], limit: Int64) throws -> Int64 {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]) else {
            throw ArcboxError("validation_failed", L("Не удалось проверить результат распаковки."))
        }
        var total: Int64 = 0
        let expectedFiles = Dictionary(uniqueKeysWithValues: expected.filter { !$0.isDirectory }.map { ($0.path, $0) })
        var actualFiles = Set<String>()
        for case let url as URL in walker {
            let relative = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            try validateName(relative)
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else {
                throw ArcboxError("unsafe_link", L("Распаковка остановлена: обнаружена ссылка или специальный файл."))
            }
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
            guard total <= limit else { throw ArcboxError("size_limit", L("Распакованные данные превысили лимит.")) }
            if values.isRegularFile == true {
                guard let expectedEntry = expectedFiles[relative], !expectedEntry.sizeKnown || expectedEntry.size == Int64(values.fileSize ?? 0) else {
                    throw ArcboxError("validation_failed", L("Имена или размеры распакованных файлов отличаются от списка архива."))
                }
                actualFiles.insert(relative)
                // Preserve executable files, remove setuid/setgid and quarantine every extracted file.
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
                try FileManager.default.setAttributes([.posixPermissions: mode & 0o777], ofItemAtPath: url.path)
                let quarantine = "0081;\(String(Int(Date().timeIntervalSince1970), radix: 16));Arcbox;"
                _ = quarantine.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
            }
        }
        guard actualFiles == Set(expectedFiles.keys) else {
            throw ArcboxError("validation_failed", L("Распакованы не все выбранные файлы."))
        }
        return total
    }
}
