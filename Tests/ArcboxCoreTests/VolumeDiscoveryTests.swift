import Foundation
import XCTest

@testable import ArcboxCore

final class VolumeDiscoveryTests: TestWorkspace {
    func testNativeRarAndZipNamingConventions() throws {
        for names in [
            ["movie.part01.rar", "movie.part02.rar"], ["legacy.rar", "legacy.r00", "legacy.r01"],
            ["split.z01", "split.z02", "split.zip"],
        ] {
            let urls = try names.map { try file($0) }
            let set = try XCTUnwrap(engine.volumes(for: try XCTUnwrap(urls.first)))
            XCTAssertEqual(set.count, names.count)
            XCTAssertEqual(Set(set.paths.map { URL(fileURLWithPath: $0).lastPathComponent }), Set(names))
            XCTAssertEqual(
                URL(fileURLWithPath: set.firstPart).resolvingSymlinksInPath(),
                urls[names.last == "split.zip" ? names.count - 1 : 0].resolvingSymlinksInPath())
        }
        let missing = try file("missing.part02.rar")
        expectCode("missing_parts") { _ = try engine.volumes(for: missing) }
        let legacyMissing = try file("missing.r00")
        expectCode("missing_parts") { _ = try engine.volumes(for: legacyMissing) }
        let zipMissing = try file("gap.z02")
        _ = try file("gap.zip")
        expectCode("missing_parts") { _ = try engine.volumes(for: zipMissing) }
        XCTAssertNil(try engine.volumes(for: try file("single.zip")))
    }

    func testCompressedTarContentsAreExposed() throws {
        let source = try file("payload.txt")
        let tar = root.appendingPathComponent("bundle.tar")
        _ = try engine.create(inputs: [source], output: tar, format: "tar")
        let compressed = root.appendingPathComponent("bundle.tar.gz")
        _ = try engine.run(["a", "-tgzip", "--", compressed.path, tar.path], password: "", token: .init())
        XCTAssertEqual(try engine.list(compressed).entries.first?.path, "payload.txt")
        let destination = root.appendingPathComponent("restored")
        _ = try engine.extract(compressed, to: destination)
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("payload.txt")), try Data(contentsOf: source))
    }

    func testManifestTamperingIsRejected() throws {
        let source = try file("payload", Data(count: 16))
        let parts = root.appendingPathComponent("parts")
        _ = try engine.create(inputs: [source], output: parts, format: "parts", partBytes: 8)
        let first = parts.appendingPathComponent("payload.001")
        let manifest = parts.appendingPathComponent("payload.arcbox-parts.json")
        let data = try Data(contentsOf: manifest)
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        value["contentKind"] = "unknown"
        try JSONSerialization.data(withJSONObject: value).write(to: manifest)
        expectCode("invalid_manifest") { _ = try engine.list(first) }
        try data.write(to: manifest)
        try Data(count: 7).write(to: parts.appendingPathComponent("payload.002"))
        expectCode("part_corrupt") { _ = try engine.list(first) }
        try Data(repeating: 1, count: 8).write(to: parts.appendingPathComponent("payload.002"))
        expectCode("part_corrupt") { _ = try engine.test(first) }
    }
}
