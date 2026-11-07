import ArcboxCore
import Foundation

struct CommandArguments {
    var values: [String: Any] = [:]
    private var paths: [String] = []
    private var entries: [String] = []
    private var passwordFromInput = false

    init(_ raw: [String], command: String) throws {
        try parse(raw)
        if command == "create" {
            values["inputs"] = paths
        } else {
            guard paths.count == 1 else {
                throw ArcboxError("invalid_arguments", "Expected one archive path. Use --help.")
            }
            let key = command == "split" ? "file" : command == "join" ? "firstPart" : "archive"
            values[key] = paths[0]
        }
        values["entries"] = entries
        if passwordFromInput { values["password"] = readLine() ?? "" }
    }

    private mutating func parse(_ raw: [String]) throws {
        var index = 0
        var literal = false
        while index < raw.count {
            let item = raw[index]
            index += 1
            if literal { paths.append(item); continue }
            if item == "--" { literal = true; continue }
            if item == "--password-stdin" { passwordFromInput = true; continue }
            guard item.hasPrefix("--") else { paths.append(item); continue }
            guard index < raw.count else { throw ArcboxError("invalid_arguments", "Missing value for \(item)") }
            try option(item, value: raw[index])
            index += 1
        }
    }

    private mutating func option(_ name: String, value: String) throws {
        switch name {
        case "--to": values["destination"] = value
        case "--output": values["output"] = value
        case "--format": values["format"] = value
        case "--entry": entries.append(value)
        case "--level":
            guard let level = Int(value) else { throw ArcboxError("invalid_arguments", "Invalid level") }
            values["level"] = level
        case "--limit-bytes": values["limitBytes"] = try positive(value, label: "limit")
        case "--part-bytes": values["partBytes"] = try positive(value, label: "part size")
        default: throw ArcboxError("invalid_arguments", "Unknown option \(name)")
        }
    }

    private func positive(_ value: String, label: String) throws -> Int64 {
        guard let number = Int64(value), number > 0 else { throw ArcboxError("invalid_arguments", "Invalid \(label)") }
        return number
    }
}
