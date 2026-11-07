import ArcboxCore
import Foundation

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

let mcpProtocolVersions = ["2024-11-05", "2025-03-26", "2025-06-18"]

let capabilities: [String: Any] = [
    "name": "Arcbox", "version": ArchiveEngine.version,
    "operations": ["list", "test", "extract", "create", "split", "join"],
    "createFormats": ["zip", "7z", "tar", "parts"],
    "automaticVolumeDiscovery": true,
    "readFormats": [
        "zip", "7z", "rar", "tar", "gz", "bz2", "xz", "zst", "cab", "iso", "dmg",
        "and other formats supported by bundled 7-Zip",
    ],
    "interfaces": ["cli-json", "mcp-stdio", "macOS GUI"],
    "overwrite": false, "extractSymlinks": false,
    "defaultExtractLimitBytes": ArchiveEngine.defaultLimit,
    "mcpProtocolVersions": mcpProtocolVersions,
]
