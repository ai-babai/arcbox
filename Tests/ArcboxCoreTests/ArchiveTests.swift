import Foundation
import XCTest

@testable import ArcboxCore

final class ArchiveTests: TestWorkspace {
    func testRoundTripsAndSelection() throws {
        let contents = Data((0..<4096).map { UInt8($0 % 251) })
        let source = try file("input/данные.bin", contents)
        _ = try file("input/nested/note.txt")
        let folder = source.deletingLastPathComponent()
        for format in ["zip", "7z", "tar"] {
            let archive = root.appendingPathComponent("archive.\(format)")
            _ = try engine.create(inputs: [folder], output: archive, format: format)
            let info = try engine.list(archive)
            XCTAssertEqual(info.fileCount, 2)
            XCTAssertEqual(try engine.test(archive).files, 2)
            let destination = root.appendingPathComponent("out-\(format)")
            _ = try engine.extract(archive, to: destination, entries: ["input/данные.bin"])
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("input/данные.bin")), contents)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: destination.appendingPathComponent("input/nested").path))
            expectCode("destination_exists") { _ = try engine.extract(archive, to: destination) }
            expectCode("size_limit") {
                _ = try engine.extract(archive, to: root.appendingPathComponent("too-large"), limit: 1)
            }
            expectCode("entry_missing") {
                _ = try engine.extract(archive, to: root.appendingPathComponent("missing"), entries: ["absent"])
            }
        }
        XCTAssertEqual(try Data(contentsOf: source), contents)
        try assertNoStaging()
    }

    func testMultipartArchiveOpensFromAnyPartAndManifest() throws {
        let data = Data((0..<8192).map { UInt8($0 % 251) })
        let source = try file("payload.bin", data)
        for format in ["zip", "7z", "tar", "parts"] {
            let output = root.appendingPathComponent("set-\(format)")
            let result = try engine.create(inputs: [source], output: output, format: format, partBytes: 128)
            let first = URL(fileURLWithPath: try XCTUnwrap(result.firstPart))
            let middle = first.deletingPathExtension().appendingPathExtension("002")
            let manifest = first.deletingPathExtension().appendingPathExtension("arcbox-parts.json")
            for selected in [first, middle, manifest] {
                let info = try engine.list(selected)
                XCTAssertEqual(info.fileCount, 1)
                XCTAssertEqual(info.volumes?.count, result.parts)
                XCTAssertEqual(info.isFileParts, format == "parts")
                XCTAssertEqual(try engine.test(selected).files, 1)
            }
            let destination = root.appendingPathComponent("restored-\(format)")
            _ = try engine.extract(middle, to: destination)
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("payload.bin")), data)
        }
    }

    func testEncryptedArchivesAndBadPasswords() throws {
        let source = try file("secret.txt")
        for format in ["zip", "7z"] {
            let archive = root.appendingPathComponent("secret.\(format)")
            _ = try engine.create(inputs: [source], output: archive, format: format, password: "test secret")
            expectCode("password_required") { _ = try engine.test(archive, password: "wrong") }
            XCTAssertEqual(try engine.test(archive, password: "test secret").files, 1)
            let destination = root.appendingPathComponent("unlocked-\(format)")
            _ = try engine.extract(archive, to: destination, password: "test secret")
            XCTAssertEqual(
                try Data(contentsOf: source), try Data(contentsOf: destination.appendingPathComponent("secret.txt")))
        }
    }

    func testInvalidCreationAndCancellation() throws {
        let source = try file("input/file")
        let output = root.appendingPathComponent("out")
        expectCode("invalid_arguments") { _ = try engine.create(inputs: [], output: output) }
        expectCode("invalid_arguments") { _ = try engine.create(inputs: [source], output: output, format: "rar") }
        expectCode("invalid_arguments") { _ = try engine.create(inputs: [source], output: output, level: 10) }
        expectCode("invalid_arguments") {
            _ = try engine.create(inputs: [source], output: output, format: "tar", password: "secret")
        }
        expectCode("different_parents") { _ = try engine.create(inputs: [source, try file("other")], output: output) }
        expectCode("invalid_destination") {
            _ = try engine.create(
                inputs: [source.deletingLastPathComponent()], output: source.appendingPathComponent("nested.zip"))
        }
        expectCode("invalid_password") {
            _ = try engine.create(inputs: [source], output: output, password: "line\nbreak")
        }
        let token = OperationToken()
        token.cancel()
        expectCode("cancelled") { _ = try engine.create(inputs: [source], output: output, token: token) }
        expectCode("file_missing") { _ = try engine.list(output) }
        expectCode("destination_exists") { _ = try engine.create(inputs: [source], output: source) }
        try assertNoStaging()
    }
}
