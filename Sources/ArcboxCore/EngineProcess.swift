import Foundation

extension ArchiveEngine {
    func run(
        _ arguments: [String], password: String, directory: URL? = nil, token: OperationToken, writeRoot: URL? = nil,
        byteLimit: Int64? = nil
    ) throws -> String {
        try token.check()
        try validatePassword(password)
        let child = Process()
        try configure(child, arguments: arguments, writeRoot: writeRoot)
        child.currentDirectoryURL = directory
        child.environment = [
            "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
        ]
        let stdout = Pipe()
        let stdin = Pipe()
        child.standardOutput = stdout
        child.standardError = stdout
        child.standardInput = stdin
        try token.launch(child)
        defer { token.clear() }
        stdin.fileHandleForWriting.write(Data((password + "\n" + password + "\n").utf8))
        try? stdin.fileHandleForWriting.close()
        let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        let started = Date()
        watchdog.schedule(deadline: .now() + 1, repeating: 1)
        watchdog.setEventHandler {
            if Date().timeIntervalSince(started) > 1800 { token.cancel() }
            if let root = writeRoot, let limit = byteLimit, exceedsLimit(root, limit: limit) { token.cancel() }
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
        if child.terminationStatus != 0 { throw engineFailure(output, status: child.terminationStatus) }
        return output
    }

    private func configure(_ child: Process, arguments: [String], writeRoot: URL?) throws {
        // macOS Seatbelt confines extraction writes, including writes through archive symlinks.
        if let root = writeRoot {
            guard let resolved = realpath(root.path, nil) else {
                throw ArcboxError("invalid_destination", L("Не удалось разрешить путь папки."))
            }
            let canonical = String(cString: resolved)
            free(resolved)
            let literal = canonical.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
                of: "\"", with: "\\\"")
            let profile =
                "(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (subpath \"\(literal)\") (literal \"/dev/null\"))"
            child.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            child.arguments = ["-p", profile, executable.path] + arguments
        } else {
            child.executableURL = executable
            child.arguments = arguments
        }
    }

    private func exceedsLimit(_ root: URL, limit: Int64) -> Bool {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return false
        }
        var size: Int64 = 0
        for case let url as URL in walker {
            size += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if size > limit { return true }
        }
        return false
    }

    private func engineFailure(_ output: String, status: Int32) -> ArcboxError {
        let lower = output.lowercased()
        if lower.contains("missing volume") || lower.contains("cannot find volume") {
            return ArcboxError(
                "missing_parts", L("Не хватает тома архива. Положи все части рядом и повтори операцию."))
        }
        if lower.contains("password") || lower.contains("encrypted") {
            return ArcboxError("password_required", L("Нужен правильный пароль для этого архива."))
        }
        let detail = output.components(separatedBy: .newlines).filter {
            $0.contains("ERROR") || $0.contains("Error") || $0.contains("Denied")
        }.prefix(4).joined(separator: "\n")
        return ArcboxError(
            "engine_error",
            detail.isEmpty
                ? L(
                    "Не удалось обработать архив (код %@). Возможно, он повреждён или формат не поддерживается.",
                    String(describing: (status))) : detail)
    }
    private func validatePassword(_ password: String) throws {
        guard !password.contains("\n"), !password.contains("\r"), !password.contains("\0") else {
            throw ArcboxError("invalid_password", L("Пароль не должен содержать перевод строки или нулевой символ."))
        }
    }
}
