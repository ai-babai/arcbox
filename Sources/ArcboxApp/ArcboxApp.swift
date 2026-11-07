import SwiftUI
import AppKit
import ArcboxCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: ArchiveModel?
    var pending: URL?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        if let model { model.acceptDrop([first]) } else { pending = first }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.cleanup() }
}

@main struct ArcboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = ArchiveModel()
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("language") private var language = "system"
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .environment(\.locale, AppLanguage.locale)
                .id(language)
                .onChange(of: language) { _, _ in model.refreshLanguage() }
                .onChange(of: appearance) { _, _ in applyAppearance() }
                .onAppear {
                    applyAppearance()
                    delegate.model = model
                    if let pending = delegate.pending { delegate.pending = nil; model.acceptDrop([pending]) }
                    else if let index = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.count > index + 1 {
                        model.open(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                    }
                }
                .onOpenURL { model.acceptDrop([$0]) }
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("Открыть архив…"), action: model.openPanel).keyboardShortcut("o").disabled(model.busy)
                Button(L("Создать архив…"), action: model.newArchive).keyboardShortcut("n").disabled(model.busy)
            }
            CommandMenu(L("Архив")) {
                Button(L("Распаковать всё…")) { model.extract(selected: false) }.keyboardShortcut("e").disabled(model.info == nil || model.busy)
                Button(L("Распаковать выбранное…")) { model.extract(selected: true) }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.selection.isEmpty || model.busy)
                Button(L("Проверить целостность"), action: model.test).keyboardShortcut("t", modifiers: [.command, .shift]).disabled(model.info == nil || model.busy)
                Button(L("Быстрый просмотр"), action: model.preview).keyboardShortcut("y").disabled(model.selection.isEmpty || model.busy)
            }
            CommandGroup(after: .toolbar) {
                Picker(L("Язык"), selection: $language) {
                    Text(L("Как в системе")).tag("system")
                    Text("English").tag("en"); Text(L("Русский")).tag("ru")
                }
                Toggle(L("Боковая панель"), isOn: $model.showSidebar).keyboardShortcut("s", modifiers: [.command, .control])
                Picker(L("Оформление"), selection: $appearance) {
                    Text(L("Как в системе")).tag("system"); Text(L("Светлое")).tag("light"); Text(L("Тёмное")).tag("dark")
                }
                Toggle(L("Инспектор"), isOn: $model.showInspector).keyboardShortcut("i", modifiers: [.command, .option])
                Button(L("Инструменты агента")) { model.showAgent = true }.keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
    private func applyAppearance() {
        NSApp.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
    }
}
