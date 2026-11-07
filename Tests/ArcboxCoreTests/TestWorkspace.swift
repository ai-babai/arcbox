import Foundation
import XCTest

@testable import ArcboxCore

class TestWorkspace: XCTestCase {
    var root: URL!
    var engine: ArchiveEngine!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
            "Arcbox-tests-\(UUID().uuidString)"
        )
        .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let binary = ProcessInfo.processInfo.environment["ARCBOX_ENGINE"] ?? "vendor/7zip/7zz"
        engine = try ArchiveEngine(executable: URL(fileURLWithPath: binary))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func file(_ name: String, _ data: Data = Data("Archive contents.\n".utf8)) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func expectCode(_ code: String, _ operation: () throws -> Void, file: StaticString = #filePath, line: UInt = #line)
    {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual((error as? ArcboxError)?.code, code, "\(error)", file: file, line: line)
        }
    }

    func assertNoStaging(file: StaticString = #filePath, line: UInt = #line) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".arcbox-") }, file: file, line: line)
    }
}
