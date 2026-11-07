import Foundation
import SwiftCheck
import XCTest

@testable import ArcboxCore

final class ArchivePolicyTests: TestWorkspace {
    func testTraversalPathsAreRejected() {
        property("A parent component is unsafe at any generated depth")
            <- forAll { (depth: UInt8) in
                let path = Array(repeating: "folder", count: Int(depth % 10)) + ["..", "payload"]
                do {
                    try self.engine.validateName(path.joined(separator: "/"))
                    return false
                } catch { return (error as? ArcboxError)?.code == "unsafe_path" }
            }
        for path in [
            "", "/absolute", "../file", "folder/./file", "C:\\file", "folder\\..\\file", "line\nbreak", "null\0byte",
        ] {
            expectCode("unsafe_path") { try engine.validateName(path) }
        }
        for path in ["folder/файл.txt", "some space.txt", "a-b_c", "emoji-📦"] {
            XCTAssertNoThrow(try engine.validateName(path))
        }
    }

    func testAmbiguousListingIsRejected() throws {
        for text in ["Path = first\nPath = second\nSize = 1", "not a field"] {
            expectCode("ambiguous_name") { _ = try engine.parseListing(text, fallbackName: "file") }
        }
        for text in ["Path = x\nSize = -1", "Path = x"] {
            expectCode("invalid_archive") { _ = try engine.parseListing(text, fallbackName: "file") }
        }
        let entries = try engine.parseListing(
            "Path = folder\nFolder = +\n\nSize = 3\nEncrypted = +\n", fallbackName: "fallback")
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertFalse(entries[0].sizeKnown)
        XCTAssertEqual(entries[1].path, "fallback")
        XCTAssertTrue(entries[1].encrypted)
    }

    func testCollisionsLinksAndSizeOverflowAreRejected() throws {
        let entries = try engine.parseListing("Path = Name\nSize = 1\n\nPath = name\nSize = 2", fallbackName: "file")
        expectCode("path_collision") { try engine.validateEntries(entries) }
        for field in ["Symbolic Link = target", "Hard Link = target", "Attributes = lrwxrwxrwx", "Attributes = A lrwx"]
        {
            let links = try engine.parseListing("Path = link\nSize = 0\n\(field)", fallbackName: "file")
            expectCode("unsafe_link") { try engine.validateEntries(links) }
        }
        let huge = try engine.parseListing(
            "Path = one\nSize = \(Int64.max)\n\nPath = two\nSize = 1", fallbackName: "file")
        expectCode("size_limit") { _ = try engine.sumSizes(huge) }
    }

    func testOutputValidationRejectsUnexpectedOrMissingFiles() throws {
        let output = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let expected = try engine.parseListing("Path = expected\nSize = 3", fallbackName: "file")
        expectCode("validation_failed") { _ = try engine.validateExtracted(output, expected: expected, limit: 10) }
        try Data([1, 2, 3]).write(to: output.appendingPathComponent("unexpected"))
        expectCode("validation_failed") { _ = try engine.validateExtracted(output, expected: expected, limit: 10) }
        try FileManager.default.removeItem(at: output.appendingPathComponent("unexpected"))
        try Data([1, 2]).write(to: output.appendingPathComponent("expected"))
        expectCode("validation_failed") { _ = try engine.validateExtracted(output, expected: expected, limit: 10) }
        try Data([1, 2, 3]).write(to: output.appendingPathComponent("expected"))
        expectCode("size_limit") { _ = try engine.validateExtracted(output, expected: expected, limit: 2) }
        XCTAssertEqual(try engine.validateExtracted(output, expected: expected, limit: 3), 3)
        try FileManager.default.removeItem(at: output.appendingPathComponent("expected"))
        try FileManager.default.createSymbolicLink(
            atPath: output.appendingPathComponent("expected").path, withDestinationPath: "/tmp")
        expectCode("unsafe_link") { _ = try engine.validateExtracted(output, expected: expected, limit: 10) }
    }
}
