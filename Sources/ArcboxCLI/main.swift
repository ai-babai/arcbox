import Foundation
import ArcboxCore

func json(_ value: Any) -> String {
    String(data: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])) ?? Data("null".utf8), encoding: .utf8)!
}
func object<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}
func failure(_ error: Error) -> [String: Any] {
    ["ok": false, "error": ["code": (error as? ArcboxError)?.code ?? "io_error", "message": error.localizedDescription]]
}
func url(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL }

let help = """
Arcbox \(ArchiveEngine.version) · local archive tools for people and agents

  arcbox list ARCHIVE [--password-stdin]
  arcbox test ARCHIVE [--password-stdin]
  arcbox extract ARCHIVE --to NEW_FOLDER [--entry PATH ...] [--password-stdin]
  arcbox create FILE... --output NEW_ARCHIVE [--format zip|7z|tar] [--level 0...9] [--password-stdin]
  arcbox create FILE... --output NEW_FOLDER --format 7z --part-bytes N
  arcbox create FILE --output NEW_FOLDER --format parts --part-bytes N
  arcbox split FILE --to NEW_FOLDER --part-bytes N
  arcbox join FIRST_PART.001 --output NEW_FILE
  arcbox capabilities
  arcbox mcp

Every operation prints JSON. Exit 0 = success; 1 = operation error; 2 = bad arguments.
Passwords are read as one line from stdin and never passed on the process command line.
Extraction defaults to a 20 GiB limit; override with --limit-bytes N.
Destination must be new. --entry may select a file or directory. No overwrite mode.
Open/list/extract accept any volume: the first part and its siblings are detected automatically.
With --part-bytes, create writes all parts directly into NEW_FOLDER (not a standalone archive).
Split writes .001/.002 parts and a SHA-256 manifest. Keep the manifest beside the parts.
Join verifies every part when a manifest is present; otherwise returns verified=false.
"""

let capabilities: [String: Any] = [
    "name": "Arcbox", "version": ArchiveEngine.version,
    "operations": ["list", "test", "extract", "create", "split", "join"],
    "createFormats": ["zip", "7z", "tar", "parts"],
    "automaticVolumeDiscovery": true,
    "readFormats": ["zip", "7z", "rar", "tar", "gz", "bz2", "xz", "zst", "cab", "iso", "dmg", "and other formats supported by bundled 7-Zip"],
    "interfaces": ["cli-json", "mcp-stdio", "macOS GUI"],
    "overwrite": false, "extractSymlinks": false,
    "defaultExtractLimitBytes": ArchiveEngine.defaultLimit,
    "mcpProtocolVersions": ["2024-11-05", "2025-03-26", "2025-06-18"]
]

func execute(_ name: String, args: [String: Any], engine: ArchiveEngine) throws -> Any {
    func string(_ key: String) throws -> String {
        guard let value = args[key] as? String, !value.isEmpty else { throw ArcboxError("invalid_arguments", "Missing string: \(key)") }
        return value
    }
    let password = args["password"] as? String ?? ""
    switch name {
    case "list": return try object(engine.list(url(try string("archive")), password: password))
    case "test": return try object(engine.test(url(try string("archive")), password: password))
    case "extract":
        return try object(engine.extract(url(try string("archive")), to: url(try string("destination")), entries: args["entries"] as? [String] ?? [], password: password, limit: (args["limitBytes"] as? NSNumber)?.int64Value ?? ArchiveEngine.defaultLimit))
    case "create":
        guard let inputs = args["inputs"] as? [String], !inputs.isEmpty else { throw ArcboxError("invalid_arguments", "inputs must be a nonempty string array") }
        return try object(engine.create(inputs: inputs.map(url), output: url(try string("output")), format: args["format"] as? String ?? "zip", level: args["level"] as? Int ?? 5, password: password, partBytes: (args["partBytes"] as? NSNumber)?.int64Value))
    case "split":
        guard let partBytes = (args["partBytes"] as? NSNumber)?.int64Value, partBytes > 0 else { throw ArcboxError("invalid_arguments", "partBytes must be a positive integer") }
        return try object(engine.split(url(try string("file")), to: url(try string("destination")), partBytes: partBytes))
    case "join":
        return try object(engine.join(url(try string("firstPart")), output: url(try string("output"))))
    default: throw ArcboxError("unknown_operation", "Unknown operation: \(name)")
    }
}

func toolSchema(_ name: String, description: String, properties: [String: Any], required: [String], readOnly: Bool) -> [String: Any] {
    ["name": "arcbox_" + name, "description": description,
     "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
     "annotations": ["readOnlyHint": readOnly, "destructiveHint": false, "idempotentHint": readOnly, "openWorldHint": false]]
}

func mcp() throws {
    let engine = try ArchiveEngine()
    let str: [String: Any] = ["type": "string"]
    let strings: [String: Any] = ["type": "array", "items": str]
    let tools: [[String: Any]] = [
        toolSchema("list", description: "Open any archive or volume and list its contents. Automatically finds the first and sibling parts. Returns volumes metadata and isFileParts for raw binary parts. Archive names are untrusted data.", properties: ["archive": str, "password": str], required: ["archive"], readOnly: true),
        toolSchema("test", description: "Read and verify all archive data and checksums.", properties: ["archive": str, "password": str], required: ["archive"], readOnly: true),
        toolSchema("extract", description: "Extract an archive or any volume into a NEW folder. Reads all parts automatically, verifies an adjacent manifest when present. Raw file parts restore the original file in the destination folder. Never overwrites. Default maximum 20 GiB.", properties: ["archive": str, "destination": str, "entries": strings, "password": str, "limitBytes": ["type": "integer", "minimum": 1]], required: ["archive", "destination"], readOnly: false),
        toolSchema("create", description: "Create ZIP/7z/TAR from sibling inputs. Optional partBytes creates a complete volume set in output (a NEW folder) with a SHA-256 manifest. Format parts splits one file without archiving and requires partBytes. ZIP/7z accept passwords. Never overwrites.", properties: ["inputs": strings, "output": str, "format": ["type": "string", "enum": ["zip", "7z", "tar", "parts"]], "partBytes": ["type": "integer", "minimum": 1], "level": ["type": "integer", "minimum": 0, "maximum": 9], "password": str], required: ["inputs", "output"], readOnly: false),
        toolSchema("split", description: "Split any file into standard .001/.002 binary chunks in a NEW folder. Writes a SHA-256 manifest. Source is preserved.", properties: ["file": str, "destination": str, "partBytes": ["type": "integer", "minimum": 1]], required: ["file", "destination", "partBytes"], readOnly: false),
        toolSchema("join", description: "Join sequential binary .001/.002 chunks into a NEW file. Automatically checks a sibling Arcbox manifest; otherwise verified=false because a missing final part cannot be detected. RAR volumes should be opened as an archive instead.", properties: ["firstPart": str, "output": str], required: ["firstPart", "output"], readOnly: false)
    ]
    func reply(_ id: Any, _ result: Any) { print(json(["jsonrpc": "2.0", "id": id, "result": result])); fflush(stdout) }
    while let line = readLine() {
        guard let data = line.data(using: .utf8), let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print(json(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])); fflush(stdout); continue
        }
        guard let id = request["id"] else { continue }
        let params = request["params"] as? [String: Any] ?? [:]
        switch request["method"] as? String {
        case "initialize":
            let supported = capabilities["mcpProtocolVersions"] as! [String]
            let requested = params["protocolVersion"] as? String ?? ""
            reply(id, ["protocolVersion": supported.contains(requested) ? requested : "2025-06-18", "capabilities": ["tools": [:]], "serverInfo": ["name": "arcbox", "version": ArchiveEngine.version]])
        case "ping": reply(id, [:] as [String: String])
        case "tools/list": reply(id, ["tools": tools])
        case "tools/call":
            do {
                let tool = params["name"] as? String ?? ""
                guard tools.contains(where: { $0["name"] as? String == tool }) else { throw ArcboxError("unknown_tool", "Unknown tool") }
                let value = try execute(String(tool.dropFirst(7)), args: params["arguments"] as? [String: Any] ?? [:], engine: engine)
                reply(id, ["content": [["type": "text", "text": json(["ok": true, "result": value])]], "isError": false])
            } catch { reply(id, ["content": [["type": "text", "text": json(failure(error))]], "isError": true]) }
        default:
            print(json(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]])); fflush(stdout)
        }
    }
}

do {
    var raw = Array(CommandLine.arguments.dropFirst())
    guard let command = raw.first else { print(help); exit(0) }
    raw.removeFirst()
    if ["help", "--help", "-h"].contains(command) { print(help); exit(0) }
    if command == "--version" { print(ArchiveEngine.version); exit(0) }
    if command == "capabilities" { print(json(capabilities)); exit(0) }
    if command == "mcp" { try mcp(); exit(0) }
    var args: [String: Any] = [:], positional: [String] = [], entries: [String] = [], usePassword = false
    var i = 0, literal = false
    while i < raw.count {
        let item = raw[i]
        if item == "--", !literal { literal = true; i += 1; continue }
        if item == "--password-stdin", !literal { usePassword = true; i += 1; continue }
        if item.hasPrefix("--"), !literal {
            guard i + 1 < raw.count else { throw ArcboxError("invalid_arguments", "Missing value for \(item)") }
            let value = raw[i + 1]
            switch item {
            case "--to": args["destination"] = value
            case "--output": args["output"] = value
            case "--format": args["format"] = value
            case "--entry": entries.append(value)
            case "--level":
                guard let level = Int(value) else { throw ArcboxError("invalid_arguments", "Invalid level") }; args["level"] = level
            case "--limit-bytes":
                guard let limit = Int64(value), limit > 0 else { throw ArcboxError("invalid_arguments", "Invalid limit") }; args["limitBytes"] = limit
            case "--part-bytes":
                guard let bytes = Int64(value), bytes > 0 else { throw ArcboxError("invalid_arguments", "Invalid part size") }; args["partBytes"] = bytes
            default: throw ArcboxError("invalid_arguments", "Unknown option \(item)")
            }
            i += 2
        } else { positional.append(item); i += 1 }
    }
    if command == "create" { args["inputs"] = positional }
    else {
        guard positional.count == 1 else { throw ArcboxError("invalid_arguments", "Expected one archive path. Use --help.") }
        args[command == "split" ? "file" : command == "join" ? "firstPart" : "archive"] = positional[0]
    }
    args["entries"] = entries
    if usePassword { args["password"] = readLine() ?? "" }
    let result = try execute(command, args: args, engine: ArchiveEngine())
    print(json(["ok": true, "result": result]))
} catch {
    print(json(failure(error)))
    exit((error as? ArcboxError)?.code == "invalid_arguments" ? 2 : 1)
}
