import ArcboxCore
import Foundation

func runCommand() throws {
    let raw = Array(CommandLine.arguments.dropFirst())
    guard let command = raw.first else { print(help); return }
    switch command {
    case "help", "--help", "-h": print(help)
    case "--version": print(ArchiveEngine.version)
    case "capabilities": print(json(capabilities))
    case "mcp": try mcp()
    default:
        let arguments = try CommandArguments(Array(raw.dropFirst()), command: command)
        let result = try execute(command, args: arguments.values, engine: ArchiveEngine())
        print(json(["ok": true, "result": result]))
    }
}

do { try runCommand() } catch {
    print(json(failure(error)))
    exit((error as? ArcboxError)?.code == "invalid_arguments" ? 2 : 1)
}
