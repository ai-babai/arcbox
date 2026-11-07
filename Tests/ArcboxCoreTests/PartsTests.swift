import Foundation
import SwiftCheck
import XCTest

@testable import ArcboxCore

final class PartsTests: TestWorkspace {
    func testSplitJoinProperty() {
        property("Joining generated binary chunks restores the exact input and preserves the source")
            <- forAll {
                (values: [UInt8], chunk: Positive<Int16>) in
                do {
                    let sample = self.root.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: false)
                    defer { try? FileManager.default.removeItem(at: sample) }
                    let data = Data(values)
                    let source = sample.appendingPathComponent("данные.bin")
                    try data.write(to: source)
                    let parts = sample.appendingPathComponent("parts")
                    let size = Int64(chunk.getPositive % 64 + 1)
                    let split = try self.engine.split(source, to: parts, partBytes: size)
                    let output = sample.appendingPathComponent("restored")
                    let joined = try self.engine.join(parts.appendingPathComponent("данные.bin.001"), output: output)
                    return try Data(contentsOf: output) == data && Data(contentsOf: source) == data
                        && joined.verified && joined.sha256 == split.sha256
                        && split.parts == max(1, (data.count + Int(size) - 1) / Int(size))
                } catch {
                    XCTFail("\(error)")
                    return false
                }
            }
    }

    func testEmptyAndBoundarySizes() throws {
        for count in [0, 1, 7, 8, 9, 1_048_577] {
            let data = Data(repeating: 0xAB, count: count)
            let source = try file("source-\(count)", data)
            let parts = root.appendingPathComponent("parts-\(count)")
            let split = try engine.split(source, to: parts, partBytes: 8_192)
            let output = root.appendingPathComponent("output-\(count)")
            let joined = try engine.join(
                parts.appendingPathComponent(source.lastPathComponent + ".001"), output: output)
            XCTAssertEqual(try Data(contentsOf: output), data)
            XCTAssertEqual(joined.bytes, Int64(count))
            XCTAssertEqual(joined.sha256, split.sha256)
        }
    }

    func testCorruptionAndMissingLastPartAreRejectedAtomically() throws {
        let source = try file("payload", Data(repeating: 7, count: 24))
        let parts = root.appendingPathComponent("parts")
        _ = try engine.split(source, to: parts, partBytes: 8)
        let first = parts.appendingPathComponent("payload.001")
        let middle = parts.appendingPathComponent("payload.002")
        let output = root.appendingPathComponent("output")
        try Data(repeating: 8, count: 8).write(to: middle)
        expectCode("part_corrupt") { _ = try engine.join(first, output: output) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        try Data(repeating: 7, count: 8).write(to: middle)
        try FileManager.default.removeItem(at: parts.appendingPathComponent("payload.003"))
        expectCode("missing_parts") { _ = try engine.join(first, output: output) }
        expectCode("missing_parts") { _ = try engine.volumes(for: middle) }
        try assertNoStaging()
    }

    func testWithoutManifestReportsUnverified() throws {
        let source = try file("payload", Data([1, 2, 3]))
        let parts = root.appendingPathComponent("parts")
        _ = try engine.split(source, to: parts, partBytes: 2)
        try FileManager.default.removeItem(at: parts.appendingPathComponent("payload.arcbox-parts.json"))
        let result = try engine.join(
            parts.appendingPathComponent("payload.001"), output: root.appendingPathComponent("out"))
        XCTAssertFalse(result.verified)
        XCTAssertEqual(result.parts, 2)
    }

    func testInvalidSplitAndExistingDestinations() throws {
        let source = try file("payload")
        expectCode("invalid_arguments") {
            _ = try engine.split(source, to: root.appendingPathComponent("new"), partBytes: 0)
        }
        expectCode("too_many_parts") {
            _ = try engine.split(
                try file("large", Data(count: 10_001)), to: root.appendingPathComponent("new"), partBytes: 1)
        }
        expectCode("destination_exists") { _ = try engine.split(source, to: source, partBytes: 2) }
        expectCode("invalid_arguments") { _ = try engine.join(source, output: root.appendingPathComponent("out")) }
        let token = OperationToken()
        token.cancel()
        expectCode("cancelled") {
            _ = try engine.split(source, to: root.appendingPathComponent("cancel"), partBytes: 2, token: token)
        }
        try assertNoStaging()
    }
}
