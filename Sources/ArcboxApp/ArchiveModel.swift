import SwiftUI
import AppKit
import ArcboxCore
import UniformTypeIdentifiers

struct BrowserRow: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let directory: Bool
    let size: Int64
    let encrypted: Bool
    let modified: String
    var symbol: String {
        if directory { return "folder.fill" }
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "png", "webp", "heic", "gif", "svg": return "photo"
        case "mp4", "mov", "mkv": return "film"
        case "mp3", "wav", "flac", "m4a": return "waveform"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox"
        case "pdf": return "doc.richtext"
        case "swift", "js", "py", "rs", "json", "html", "css": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}

enum ArchiveActivity: String {
    case reading = "Читаю архив…"
    case checking = "Проверяю целостность…"
    case extracting = "Распаковываю…"
    case previewing = "Готовлю просмотр…"
    case creating = "Создаю архив…"
    var title: String { L(rawValue) }
}

@MainActor final class ArchiveModel: ObservableObject {
    @Published var archive: URL?
    @Published var info: ArchiveInfo?
    @Published var query = ""
    @Published var folder = ""
    @Published var selection = Set<String>()
    @Published var busy = false
    @Published private(set) var operationStarted: Date?
    @Published private(set) var operationTarget: String?
    @Published private(set) var cancelling = false
    private var activity: ArchiveActivity?
    @Published var status = L("Готово к работе")
    @Published private(set) var statusIcon = "checkmark.circle"
    @Published var error: String?
    @Published var resultURL: URL?
    @Published var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentArchives") ?? []
    @Published var showCreate = false
    @Published var showAgent = false
    @Published var canRetry = false
    @Published var showPassword = false
    @Published var passwordInput = ""
    @Published var createInputs: [URL] = []
    @Published var previewURL: URL?
    @Published var showInspector = UserDefaults.standard.object(forKey: "showInspector") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showInspector, forKey: "showInspector") }
    }
    @Published var showSidebar = UserDefaults.standard.object(forKey: "showSidebar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showSidebar, forKey: "showSidebar") }
    }
    @Published var sortOrder = [KeyPathComparator(\BrowserRow.name, order: .forward)]
    private var password = ""
    private var retry: (() -> Void)?
    private var token = OperationToken()
    private var previewRoots: [URL] = []

    var rows: [BrowserRow] {
        guard let info else { return [] }
        var result: [BrowserRow] = [], folders = Set<String>()
        let searching = !query.isEmpty
        for entry in info.entries {
            if searching {
                guard entry.path.localizedCaseInsensitiveContains(query) else { continue }
            } else {
                guard entry.path.hasPrefix(folder) else { continue }
                let remainder = String(entry.path.dropFirst(folder.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if remainder.isEmpty { continue }
                if let slash = remainder.firstIndex(of: "/") {
                    let name = String(remainder[..<slash]), path = folder + name
                    if folders.insert(path).inserted { result.append(BrowserRow(path: path, name: name, directory: true, size: 0, encrypted: false, modified: "")) }
                    continue
                }
            }
            if entry.isDirectory && !folders.insert(entry.path).inserted { continue }
            result.append(BrowserRow(path: entry.path, name: entry.name, directory: entry.isDirectory, size: entry.size, encrypted: entry.encrypted, modified: entry.modified ?? ""))
        }
        return result.sorted(using: sortOrder).sorted { $0.directory && !$1.directory }
    }
    var selectedRow: BrowserRow? { rows.first { selection.contains($0.path) } }
    var displayName: String { info?.volumes?.name ?? archive?.lastPathComponent ?? L("Архив") }
    var breadcrumbs: [String] { folder.split(separator: "/").map(String.init) }
    var cliPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/arcbox").path }
    var listCommand: String { "\(shellQuote(cliPath)) list \(shellQuote(archive?.path ?? "/path/to/archive.zip"))" }
    var mcpConfiguration: String {
        let obj: [String: Any] = ["mcpServers": ["arcbox": ["command": cliPath, "args": ["mcp"]]]]
        return String(data: try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), encoding: .utf8)!
    }

    func openPanel() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = L("Открыть архив"); panel.prompt = L("Открыть")
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func open(_ url: URL) {
        guard !busy else { return }
        archive = url; info = nil; password = ""; folder = ""; query = ""; selection = []
        load()
    }
    private func load(created: OperationResult? = nil) {
        guard let archive else { return }
        let secret = password
        perform(.reading, retry: { self.load() }, work: { engine, token in
            try engine.list(archive, password: secret, token: token)
        }) { value in
            self.archive = URL(fileURLWithPath: value.path)
            self.info = value
            self.status = value.isFileParts ? L("Файл из %@ частей. Готов к распаковке.", String(describing: (value.volumes?.count ?? 1))) : L("В архиве: %@", String(describing: (fileCount(value.fileCount))))
            if let count = created?.parts { self.status = (value.isFileParts ? L("Файл разделён.") : L("Создан архив.")) + L(" Частей: %@. Все части сохранены в одной папке.", String(describing: (count))) }
            if let created { self.resultURL = URL(fileURLWithPath: created.path) }
            self.recent.removeAll { $0 == value.path }; self.recent.insert(value.path, at: 0)
            self.recent = Array(self.recent.prefix(10)); UserDefaults.standard.set(self.recent, forKey: "recentArchives")
            NSDocumentController.shared.noteNewRecentDocumentURL(archive)
        }
    }
    func unlock() {
        password = passwordInput; passwordInput = ""; showPassword = false
        let action = retry; retry = nil; action?()
    }
    func cancelPassword() { passwordInput = ""; showPassword = false; retry = nil; statusIcon = "slash.circle"; status = L("Ввод пароля отменён") }
    func test() {
        guard let archive else { return }
        let secret = password
        perform(.checking, retry: { self.test() }, work: { engine, token in
            try engine.test(archive, password: secret, token: token)
        }) { result in self.status = L("Архив исправен. Проверено файлов: %@", String(describing: (result.files))) }
    }
    func extract(selected: Bool) {
        guard archive != nil, let info else { return }
        let panel = NSOpenPanel()
        panel.title = L("Куда распаковать?"); panel.prompt = L("Выбрать папку")
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = L("В выбранной папке будет создана новая папка с именем архива.")
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let name = displayName
        let stem = (name as NSString).deletingPathExtension
        var destination = parent.appendingPathComponent(stem)
        var index = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = parent.appendingPathComponent("\(stem) \(index)"); index += 1
        }
        // Implicit directories are expanded to exact archive entries for the CLI's strict contract.
        let paths = selected ? info.entries.filter { entry in selection.contains { entry.path == $0 || entry.path.hasPrefix($0 + "/") } }.map(\.path) : []
        extract(to: destination, paths: paths)
    }
    private func extract(to destination: URL, paths: [String]) {
        guard let archive else { return }
        let secret = password
        perform(.extracting, target: destination.lastPathComponent, retry: { self.extract(to: destination, paths: paths) }, work: { engine, token in
            try engine.extract(archive, to: destination, entries: paths, password: secret, token: token)
        }) { result in
            self.resultURL = destination
            if self.info?.isFileParts == true {
                self.status = self.info?.volumes?.hasManifest == true ? L("Файл восстановлен из частей. Контрольные суммы совпали.") : L("Файл восстановлен. Без файла проверки полнота набора не подтверждена.")
            } else {
                self.status = L("Распаковано файлов: %@", String(describing: (result.files)))
                if self.info?.volumes?.hasManifest == true { self.status += L(". Контрольные суммы частей совпали.") }
            }
        }
    }
    func preview() {
        guard let row = selectedRow, !row.directory, let archive else { return }
        guard row.size <= 50 * 1024 * 1024 else { error = L("Для просмотра распакуй файл: его размер больше 50 МБ."); return }
        let secret = password
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Arcbox-preview-\(UUID().uuidString)")
        perform(.previewing, retry: { self.preview() }, work: { engine, token in
            try engine.extract(archive, to: destination, entries: [row.path], password: secret, limit: 51 * 1024 * 1024, token: token)
        }) { _ in
            self.previewRoots.append(destination)
            self.previewURL = destination.appendingPathComponent(row.path)
            self.status = L("Быстрый просмотр")
        }
    }
    func navigate(_ path: String) { folder = path.isEmpty ? "" : path + "/"; selection = []; query = "" }
    func activate(_ row: BrowserRow) { if row.directory { navigate(row.path) } else { selection = [row.path]; preview() } }
    func newArchive() { guard !busy else { return }; createInputs = []; showCreate = true }
    func chooseInputs() {
        let panel = NSOpenPanel()
        panel.title = L("Добавить файлы и папки"); panel.prompt = L("Добавить")
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { createInputs = panel.urls }
    }
    func create(format: String, level: Int, password: String, partBytes: Int64?) {
        let panel = NSSavePanel()
        panel.title = L("Создать архив"); panel.prompt = L("Создать")
        let name = format == "parts" ? (createInputs.first?.lastPathComponent ?? L("Файл")) : (createInputs.first?.deletingPathExtension().lastPathComponent ?? L("Архив")) + "." + format
        panel.nameFieldStringValue = name + (partBytes == nil ? "" : ".parts")
        if partBytes != nil { panel.message = L("Будет создана папка с частями и файлом проверки. Отдельно собирать архив перед распаковкой не нужно.") }
        panel.directoryURL = createInputs.first?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let output = panel.url else { return }
        let inputs = createInputs
        showCreate = false
        perform(.creating, target: output.lastPathComponent, work: { engine, token in
            try engine.create(inputs: inputs, output: output, format: format, level: level, password: password, partBytes: partBytes, token: token)
        }) { result in
            self.archive = URL(fileURLWithPath: result.firstPart ?? result.path); self.password = password
            self.folder = ""; self.query = ""; self.selection = []; self.load(created: result)
        }
    }
    func acceptDrop(_ urls: [URL]) {
        guard !busy, !urls.isEmpty else { return }
        if urls.count > 1, let part = urls.first(where: { volumeKey($0) != nil }), let key = volumeKey(part),
           urls.allSatisfy({ volumeKey($0) == key || $0.lastPathComponent == key }) {
            open(part); return
        }
        if urls.count == 1, let first = urls.first, !first.hasDirectoryPath,
           (["zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "xz", "zst", "cab", "iso", "dmg", "cbz", "cbr", "jar", "war", "apk", "deb", "rpm"].contains(first.pathExtension.lowercased()) || first.pathExtension.range(of: "^([0-9]{3,5}|[rz][0-9]{2,})$", options: [.regularExpression, .caseInsensitive]) != nil || first.lastPathComponent.hasSuffix(".arcbox-parts.json")) {
            open(first)
        } else { createInputs = urls; showCreate = true }
    }
    private func volumeKey(_ url: URL) -> String? {
        let name = url.lastPathComponent
        if name.hasSuffix(".arcbox-parts.json") { return String(name.dropLast(".arcbox-parts.json".count)) }
        if name.range(of: "\\.[0-9]{3,5}$", options: .regularExpression) != nil { return url.deletingPathExtension().lastPathComponent }
        for (pattern, suffix) in [("\\.part[0-9]+\\.rar$", ".rar"), ("\\.r[0-9]{2,}$", ".rar"), ("\\.z[0-9]{2,}$", ".zip")] {
            if let range = name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) { return String(name[..<range.lowerBound]) + suffix }
        }
        return nil
    }
    func cancel() {
        guard busy, !cancelling else { return }
        cancelling = true; status = L("Отменяю…"); token.cancel()
    }
    func cleanup() { token.cancel(); for root in previewRoots { try? FileManager.default.removeItem(at: root) } }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); statusIcon = "doc.on.doc"; status = L("Скопировано") }
    func clearRecent() { recent = []; UserDefaults.standard.removeObject(forKey: "recentArchives") }
    func refreshLanguage() {
        if busy { status = cancelling ? L("Отменяю…") : activity?.title ?? status; return }
        statusIcon = "checkmark.circle"
        status = info.map { L("В архиве: %@", String(describing: (fileCount($0.fileCount)))) } ?? L("Готово к работе")
    }
    func recentName(_ path: String) -> String { volumeKey(URL(fileURLWithPath: path)) ?? (path as NSString).lastPathComponent }
    func retryOperation() { let action = retry; retry = nil; canRetry = false; error = nil; action?() }
    private func perform<T: Sendable>(_ activity: ArchiveActivity, target: String? = nil, retry: (() -> Void)? = nil, work: @escaping @Sendable (ArchiveEngine, OperationToken) throws -> T, completion: @escaping (T) -> Void) {
        guard !busy else { return }
        busy = true; cancelling = false; self.activity = activity
        operationTarget = target ?? archive?.lastPathComponent
        if operationStarted == nil { operationStarted = Date() }
        error = nil; canRetry = false; resultURL = nil; status = activity.title; token = OperationToken()
        let operationToken = token
        Task {
            do {
                let value = try await Task.detached(priority: .userInitiated) { try work(ArchiveEngine(), operationToken) }.value
                busy = false; statusIcon = "checkmark.circle"; completion(value)
                if !busy { operationStarted = nil; operationTarget = nil; cancelling = false; self.activity = nil }
            } catch {
                busy = false
                operationStarted = nil; operationTarget = nil; cancelling = false; self.activity = nil
                if (error as? ArcboxError)?.code == "password_required", let retry {
                    self.retry = retry; self.passwordInput = ""; self.showPassword = true
                    statusIcon = "lock.circle"
                    status = L("Архив защищён паролем")
                } else if (error as? ArcboxError)?.code == "cancelled" { statusIcon = "slash.circle"; status = L("Операция отменена") }
                else { statusIcon = "exclamationmark.circle"; self.retry = retry; self.canRetry = retry != nil; self.error = error.localizedDescription; status = L("Не удалось завершить операцию") }
            }
        }
    }
}

func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func bytes(_ value: Int64) -> String {
    let units = [L("Б"), L("КБ"), L("МБ"), L("ГБ"), L("ТБ")]
    var number = Double(value), index = 0
    while number >= 1024 && index < units.count - 1 { number /= 1024; index += 1 }
    let formatter = NumberFormatter()
    formatter.locale = AppLanguage.locale; formatter.maximumFractionDigits = index == 0 || number >= 100 ? 0 : 1
    return "\(formatter.string(from: NSNumber(value: number)) ?? "0") \(units[index])"
}
func fileCount(_ count: Int) -> String {
    if AppLanguage.code == "en" { return count == 1 ? "1 file" : "\(count) files" }
    let last = count % 10, hundred = count % 100
    let noun = (11...14).contains(hundred) ? L("файлов") : last == 1 ? L("файл") : (2...4).contains(last) ? L("файла") : L("файлов")
    return "\(count) \(noun)"
}
