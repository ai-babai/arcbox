import Foundation

/// Archive names are data, never absolute paths, parent traversal or control sequences.
enum ArchivePathPolicy {
    static func isSafe(_ name: String) -> Bool {
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: false)
        return !name.isEmpty && !normalized.hasPrefix("/") && !name.contains(":")
            && !parts.contains("..") && !parts.contains(".")
            && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}
