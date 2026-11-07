import Foundation
import XCTest

@testable import ArcboxCore

final class EngineProcessTests: TestWorkspace {
    func testDiagnosticsMapToStableErrorCodes() throws {
        let shell = try ArchiveEngine(executable: URL(fileURLWithPath: "/bin/sh"))
        for (message, code) in [
            ("Missing volume", "missing_parts"), ("Wrong password", "password_required"),
            ("ERROR: Broken archive", "engine_error"), ("", "engine_error"),
        ] {
            expectCode(code) {
                _ = try shell.run(
                    ["-c", "printf '%s' \"$1\"; exit 2", "diagnostic", message], password: "", token: .init())
            }
        }
        for password in ["\r", "\0", "\n"] {
            expectCode("invalid_password") { _ = try shell.run(["-c", "exit 0"], password: password, token: .init()) }
        }
    }

    func testWatchdogCancelsWhenExtractedBytesExceedLimit() throws {
        _ = try file("payload", Data(count: 64))
        let sleeper = try ArchiveEngine(executable: URL(fileURLWithPath: "/bin/sleep"))
        expectCode("cancelled") {
            _ = try sleeper.run(["10"], password: "", token: .init(), writeRoot: root, byteLimit: 1)
        }
    }

    func testCancelledTokenDoesNotLaunchProcess() throws {
        let token = OperationToken()
        token.cancel()
        let shell = try ArchiveEngine(executable: URL(fileURLWithPath: "/bin/sh"))
        let marker = root.appendingPathComponent("launched")
        expectCode("cancelled") {
            _ = try shell.run(["-c", "touch \"$1\"", "marker", marker.path], password: "", token: token)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }
}
