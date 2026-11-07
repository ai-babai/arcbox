import Foundation

extension ArchiveEngine {
    func parseListing(_ text: String, fallbackName: String) throws -> [ArchiveEntry] {
        var records: [[String: String]] = []
        var current: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            if line.isEmpty || line == "Enter password:" {
                if !current.isEmpty {
                    records.append(current)
                    current = [:]
                }
                continue
            }
            guard let range = line.range(of: " = ") else {
                throw ArcboxError("ambiguous_name", L("Неоднозначное имя файла в архиве. Операция остановлена."))
            }
            let key = String(line[..<range.lowerBound])
            let value = String(line[range.upperBound...])
            guard current[key] == nil else {
                throw ArcboxError("ambiguous_name", L("Неоднозначные метаданные архива."))
            }
            current[key] = value
        }
        if !current.isEmpty { records.append(current) }
        return try records.map { try listingEntry($0, fallbackName: fallbackName) }
    }

    private func listingEntry(_ record: [String: String], fallbackName: String) throws -> ArchiveEntry {
        let path = record["Path"] ?? fallbackName
        let sizeValue = record["Size"].flatMap(Int64.init)
        let size = sizeValue ?? 0
        guard size >= 0, record["Size"] != nil || record["Folder"] == "+" else {
            throw ArcboxError("invalid_archive", L("Не удалось прочитать список файлов."))
        }
        let attrs = record["Attributes"] ?? ""
        return ArchiveEntry(
            path: path, size: size, sizeKnown: sizeValue != nil,
            packedSize: record["Packed Size"].flatMap(Int64.init),
            isDirectory: record["Folder"] == "+" || attrs.hasPrefix("D") || attrs.contains(" dr"),
            encrypted: record["Encrypted"] == "+", modified: record["Modified"], crc: record["CRC"],
            isLink: isLink(record))
    }

    private func isLink(_ record: [String: String]) -> Bool {
        let attrs = record["Attributes"] ?? ""
        return !(record["Symbolic Link"] ?? "").isEmpty || !(record["Hard Link"] ?? "").isEmpty
            || attrs.contains(" lr") || attrs.hasPrefix("l")
    }
}
