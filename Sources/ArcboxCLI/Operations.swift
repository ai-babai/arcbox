import ArcboxCore
import Foundation

func json(_ value: Any) -> String {
    String(
        data: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]))
            ?? Data("null".utf8), encoding: .utf8)!
}
func object<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}
func failure(_ error: Error) -> [String: Any] {
    [
        "ok": false,
        "error": ["code": (error as? ArcboxError)?.code ?? "io_error", "message": error.localizedDescription],
    ]
}
func url(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL }

func execute(_ name: String, args: [String: Any], engine: ArchiveEngine) throws -> Any {
    let password = args["password"] as? String ?? ""
    switch name {
    case "list": return try object(engine.list(url(try argument("archive", in: args)), password: password))
    case "test": return try object(engine.test(url(try argument("archive", in: args)), password: password))
    case "extract":
        return try extract(args, engine: engine)
    case "create":
        return try create(args, engine: engine)
    case "split":
        guard let partBytes = (args["partBytes"] as? NSNumber)?.int64Value, partBytes > 0 else {
            throw ArcboxError("invalid_arguments", "partBytes must be a positive integer")
        }
        return try object(
            engine.split(
                url(try argument("file", in: args)), to: url(try argument("destination", in: args)),
                partBytes: partBytes))
    case "join":
        return try object(
            engine.join(url(try argument("firstPart", in: args)), output: url(try argument("output", in: args))))
    default: throw ArcboxError("unknown_operation", "Unknown operation: \(name)")
    }
}

func argument(_ key: String, in args: [String: Any]) throws -> String {
    guard let value = args[key] as? String, !value.isEmpty else {
        throw ArcboxError("invalid_arguments", "Missing string: \(key)")
    }
    return value
}

func create(_ args: [String: Any], engine: ArchiveEngine) throws -> Any {
    guard let inputs = args["inputs"] as? [String], !inputs.isEmpty else {
        throw ArcboxError("invalid_arguments", "inputs must be a nonempty string array")
    }
    return try object(
        engine.create(
            inputs: inputs.map(url), output: url(try argument("output", in: args)),
            format: args["format"] as? String ?? "zip",
            level: args["level"] as? Int ?? 5, password: args["password"] as? String ?? "",
            partBytes: (args["partBytes"] as? NSNumber)?.int64Value))

}

func extract(_ args: [String: Any], engine: ArchiveEngine) throws -> Any {
    return try object(
        engine.extract(
            url(try argument("archive", in: args)), to: url(try argument("destination", in: args)),
            entries: args["entries"] as? [String] ?? [], password: args["password"] as? String ?? "",
            limit: (args["limitBytes"] as? NSNumber)?.int64Value ?? ArchiveEngine.defaultLimit))

}
