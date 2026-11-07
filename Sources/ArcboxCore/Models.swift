import Foundation

public struct ArchiveEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public let sizeKnown: Bool
    public let packedSize: Int64?
    public let isDirectory: Bool
    public let encrypted: Bool
    public let modified: String?
    public let crc: String?
    public let isLink: Bool
    public var name: String { (path as NSString).lastPathComponent }
}

public struct ArchiveInfo: Codable, Sendable {
    public let path: String
    public let archiveBytes: Int64
    public let unpackedBytes: Int64
    public let entries: [ArchiveEntry]
    public var volumes: VolumeSet? = nil
    public var isFileParts = false
    public var fileCount: Int { entries.filter { !$0.isDirectory }.count }
    public var encrypted: Bool { entries.contains { $0.encrypted } }
    public var unpackedSizeKnown: Bool { entries.allSatisfy { $0.sizeKnown } }
}

public struct OperationResult: Codable, Sendable {
    public let operation: String
    public let path: String
    public let files: Int
    public let bytes: Int64
    public var firstPart: String? = nil
    public var parts: Int? = nil
}

public struct ArcboxError: LocalizedError, Sendable {
    public let code: String
    public let message: String
    public var errorDescription: String? { message }
    public init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }
}

/// One operation owns one token. Cancellation is also checked between process calls.
public final class OperationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    public init() {}
    public func cancel() {
        lock.lock()
        cancelled = true
        let active = process
        lock.unlock()
        if let active, active.isRunning { active.terminate() }
    }
    func check() throws {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw ArcboxError("cancelled", L("Операция отменена.")) }
    }
    func launch(_ child: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw ArcboxError("cancelled", L("Операция отменена.")) }
        try child.run()
        process = child
    }
    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }
}
