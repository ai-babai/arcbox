import Foundation

extension ArchiveEngine {
    func validateName(_ name: String) throws {
        guard ArchivePathPolicy.isSafe(name) else {
            throw ArcboxError("unsafe_path", L("Небезопасный путь в архиве: %@", String(describing: (name))))
        }
    }

    func validateEntries(_ entries: [ArchiveEntry]) throws {
        var names = Set<String>()
        for entry in entries {
            try validateName(entry.path)
            guard !entry.isLink else {
                throw ArcboxError(
                    "unsafe_link",
                    L("Архив содержит ссылку: %@. Распаковка ссылок пока отключена.", String(describing: (entry.path))))
            }
            let normalized = entry.path.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(
                in: CharacterSet(charactersIn: "/"))
            guard names.insert(normalized).inserted else {
                throw ArcboxError(
                    "path_collision", L("Имена файлов конфликтуют на macOS: %@", String(describing: (entry.path))))
            }
        }
    }

    func select(_ entries: [ArchiveEntry], paths: [String]) throws -> [ArchiveEntry] {
        if paths.isEmpty { return entries }
        for path in paths {
            guard entries.contains(where: { $0.path == path }) else {
                throw ArcboxError("entry_missing", L("В архиве нет файла %@", String(describing: (path))))
            }
        }
        return entries.filter { entry in
            paths.contains {
                entry.path == $0
                    || entry.path.hasPrefix($0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/")
            }
        }
    }

    func sumSizes(_ entries: [ArchiveEntry]) throws -> Int64 {
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
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory),
            allowDirectory || !directory.boolValue
        else {
            throw ArcboxError("file_missing", L("Файл не найден: %@", String(describing: (url.path))))
        }
    }

    func requireNewDestination(_ url: URL) throws {
        if (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil {
            throw ArcboxError(
                "destination_exists",
                L("Этот путь уже существует. Выбери новое имя: %@", String(describing: (url.lastPathComponent))))
        }
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &dir),
            dir.boolValue
        else {
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
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }

    func validateExtracted(_ root: URL, expected: [ArchiveEntry], limit: Int64) throws -> Int64 {
        guard
            let walker = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey])
        else {
            throw ArcboxError("validation_failed", L("Не удалось проверить результат распаковки."))
        }
        var total: Int64 = 0
        let expectedFiles = Dictionary(uniqueKeysWithValues: expected.filter { !$0.isDirectory }.map { ($0.path, $0) })
        var actualFiles = Set<String>()
        for case let url as URL in walker {
            let relative = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            try validateName(relative)
            let values = try url.resourceValues(forKeys: [
                .isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey,
            ])
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else {
                throw ArcboxError("unsafe_link", L("Распаковка остановлена: обнаружена ссылка или специальный файл."))
            }
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
            try checkExtractedSize(total, limit: limit)
            if values.isRegularFile == true {
                try validateOutputFile(url, expected: expectedFiles[relative], values: values)
                actualFiles.insert(relative)
            }
        }
        guard actualFiles == Set(expectedFiles.keys) else {
            throw ArcboxError("validation_failed", L("Распакованы не все выбранные файлы."))
        }
        return total
    }

    private func validateOutputFile(_ url: URL, expected: ArchiveEntry?, values: URLResourceValues) throws {
        guard let expectedEntry = expected,
            !expectedEntry.sizeKnown || expectedEntry.size == Int64(values.fileSize ?? 0)
        else {
            throw ArcboxError(
                "validation_failed", L("Имена или размеры распакованных файлов отличаются от списка архива."))
        }
        // Preserve executable files, remove setuid/setgid and quarantine every extracted file.
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        try FileManager.default.setAttributes([.posixPermissions: mode & 0o777], ofItemAtPath: url.path)
        let quarantine = "0081;\(String(Int(Date().timeIntervalSince1970), radix: 16));Arcbox;"
        _ = quarantine.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
    }
    private func checkExtractedSize(_ total: Int64, limit: Int64) throws {
        guard total <= limit else { throw ArcboxError("size_limit", L("Распакованные данные превысили лимит.")) }
    }
}
