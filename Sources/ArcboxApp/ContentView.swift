import ArcboxCore
import QuickLookUI
import SwiftUI

let accent = Color(red: 0.13, green: 0.49, blue: 0.39)

let arcboxIcon: NSImage = {
    if let url = Bundle.main.url(forResource: "Arcbox", withExtension: "icns"),
        let image = NSImage(contentsOf: url)
    {
        return image
    }
    return NSImage(named: NSImage.applicationIconName) ?? NSImage()
}()

struct ContentView: View {
    @ObservedObject var model: ArchiveModel
    @State private var targeted = false
    @AppStorage("language") private var language = "en"
    @AppStorage("sidebarWidth") private var sidebarWidth = 218.0
    @AppStorage("inspectorWidth") private var inspectorWidth = 222.0
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        browserLayout
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: model.showSidebar)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: model.showInspector)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.busy)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.info != nil)
            .clipped()
            .tint(accent)
            .frame(minWidth: 940, minHeight: 620)
            .toolbar { archiveToolbar }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14).strokeBorder(
                                accent, style: StrokeStyle(lineWidth: 3, dash: [9, 5]))
                        )
                        .padding(8).allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.acceptDrop(urls)
                return !urls.isEmpty
            } isTargeted: {
                targeted = $0
            }
            .sheet(isPresented: $model.showCreate) { CreateSheet(model: model) }
            .sheet(isPresented: $model.showAgent) { AgentSheet(model: model) }
            .sheet(isPresented: $model.showPassword) { passwordSheet }
            .sheet(isPresented: Binding(get: { model.previewURL != nil }, set: { if !$0 { model.previewURL = nil } })) {
                previewSheet
            }

            .alert(
                L("Не удалось завершить"),
                isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
            ) {
                if model.canRetry { Button(L("Повторить"), action: model.retryOperation) }
                Button(L("Понятно"), role: .cancel) { model.error = nil }
            } message: {
                Text(model.error ?? "")
            }
            .background {
                Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
            }
    }

    private var browserLayout: some View {
        GeometryReader { geometry in
            let widths = panelWidths(in: geometry.size.width)
            HStack(spacing: 0) {
                if model.showSidebar {
                    HStack(spacing: 0) {
                        sidebar.frame(width: widths.left)
                        ResizableDivider(
                            width: $sidebarWidth, actualWidth: widths.left,
                            bounds:
                                184...min(
                                    360,
                                    max(184, geometry.size.width - 480 - widths.right - (widths.right > 0 ? 16 : 8))),
                            defaultWidth: 218, direction: 1, label: L("Ширина боковой панели"))
                    }.frame(width: widths.left + 8)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 0) {
                    if model.info != nil {
                        archiveContent(
                            inspectorSize: widths.right,
                            maximumInspectorSize: max(
                                204, geometry.size.width - 480 - widths.left - (model.showSidebar ? 16 : 8)))
                    } else if model.busy {
                        ArchiveLoading(name: model.displayName).transition(.opacity)
                    } else {
                        welcome.transition(.opacity)
                    }
                    Divider()
                    statusbar
                }.background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private var previewSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.previewURL?.lastPathComponent ?? L("Просмотр")).fontWeight(.medium)
                Spacer()
                Button(L("Готово")) { model.previewURL = nil }.keyboardShortcut(.cancelAction)
            }.padding(18)
            Divider()
            if let url = model.previewURL { FilePreview(url: url).frame(minWidth: 700, minHeight: 480) }
        }
    }

    private func panelWidths(in total: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let hasInspector = model.info != nil && model.showInspector
        let handles = (model.showSidebar ? 1 : 0) + (hasInspector ? 1 : 0)
        let available = total - 480 - CGFloat(handles) * 8
        let left =
            model.showSidebar
            ? min(max(184, min(360, CGFloat(sidebarWidth))), max(184, available - (hasInspector ? 204 : 0))) : 0
        let right = hasInspector ? min(max(204, min(360, CGFloat(inspectorWidth))), max(204, available - left)) : 0
        return (left, right)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: arcboxIcon).resizable().interpolation(.high)
                    .frame(width: 36, height: 36).accessibilityHidden(true)
                Text("Arcbox").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.8)
            }.padding(.top, 24).padding(.bottom, 24).padding(.horizontal, 24)
            Label(L("Архивы"), systemImage: "square.stack.3d.up")
                .font(.system(size: 13, weight: .semibold)).padding(.vertical, 11).padding(.horizontal, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14)
            HStack {
                Text(L("НЕДАВНИЕ")).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                Spacer()
                if !model.recent.isEmpty {
                    Button(action: model.clearRecent) { Image(systemName: "xmark").font(.system(size: 9)) }
                        .buttonStyle(.plain).help(L("Очистить список недавних"))
                }
            }.foregroundStyle(.secondary).padding(.horizontal, 25).padding(.top, 30).padding(.bottom, 12)
            if model.recent.isEmpty {
                Text(L("Открытые архивы\nпоявятся здесь.")).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineSpacing(5).padding(.horizontal, 25)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(model.recent, id: \.self) { path in
                            Button {
                                model.open(URL(fileURLWithPath: path))
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "doc.zipper").foregroundStyle(.secondary)
                                    Text(model.recentName(path)).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }.font(.system(size: 12)).padding(.vertical, 9).padding(.horizontal, 12)
                                    .background(
                                        model.archive?.path == path ? Color.primary.opacity(0.06) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain).disabled(model.busy).help(path)
                        }
                    }.padding(.horizontal, 14)
                }
            }
            Spacer(minLength: 24)
        }.background(.regularMaterial)
    }

    @ToolbarContentBuilder private var archiveToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                model.showSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help(model.showSidebar ? L("Скрыть боковую панель (⌃⌘S)") : L("Показать боковую панель (⌃⌘S)"))
            .accessibilityLabel(model.showSidebar ? L("Скрыть боковую панель") : L("Показать боковую панель"))
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: model.openPanel) { Label(L("Открыть"), systemImage: "folder").labelStyle(.titleAndIcon) }
                .disabled(model.busy)
            Button(action: model.newArchive) { Label(L("Создать"), systemImage: "plus").labelStyle(.titleAndIcon) }
                .disabled(model.busy)
            Button {
                model.extract(selected: false)
            } label: {
                Label(L("Распаковать"), systemImage: "arrow.down.to.line").labelStyle(.titleAndIcon)
            }
            .disabled(model.info == nil || model.busy)
        }
        ToolbarItem(placement: .primaryAction) {
            Picker(L("Язык"), selection: Binding(get: { AppLanguage.code }, set: { language = $0 })) {
                Text("EN").tag("en")
                Text("RU").tag("ru")
            }.pickerStyle(.segmented).labelsHidden().frame(width: 88)
                .help(L("Язык"))
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.showInspector.toggle()
            } label: {
                Label(L("Инспектор"), systemImage: "sidebar.right")
            }
            .help(L("Показать или скрыть инспектор"))
            .disabled(model.info == nil)
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 0) {
                Image(nsImage: arcboxIcon).resizable().interpolation(.high)
                    .frame(width: 88, height: 88).accessibilityHidden(true)
                    .padding(.bottom, 20)
                Text(L("Всё внутри.\nВсё под рукой.")).font(.system(size: 36, weight: .semibold)).tracking(-1.1)
                    .lineSpacing(1)
                    .multilineTextAlignment(.center)
                Text(L("Открывай, собирай и распаковывай архивы."))
                    .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(
                        .top, 12)
                Button(action: model.openPanel) {
                    HStack(spacing: 10) {
                        Text(L("Открыть архив"))
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).disabled(model.busy).padding(.top, 24)
                HStack(spacing: 7) {
                    Image(systemName: "cursorarrow.and.square.on.square.dashed")
                    Text(L("Или перетащи архив в окно"))
                }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 17)
            }.frame(maxWidth: 560)
            Spacer(minLength: 32)
            Divider().frame(maxWidth: 600)
            HStack(alignment: .top, spacing: 28) {
                formatNote(L("ОТКРЫВАЕТ"), "ZIP, RAR, 7z, TAR…")
                formatNote(L("СОЗДАЁТ"), "ZIP, 7z, TAR")
                formatNote(L("ТВОИ ФАЙЛЫ"), L("Без облака и аккаунта"))
            }.frame(maxWidth: 600).padding(.top, 20).padding(.bottom, 28)
        }.padding(.horizontal, 40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func formatNote(_ title: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12))
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }

    private func archiveContent(inspectorSize: CGFloat, maximumInspectorSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            archiveHeader
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    browserToolbar
                    fileTable
                }.frame(maxWidth: .infinity)
                if model.showInspector {
                    HStack(spacing: 0) {
                        ResizableDivider(
                            width: $inspectorWidth, actualWidth: inspectorSize,
                            bounds: 204...min(360, maximumInspectorSize), defaultWidth: 222,
                            direction: -1, label: L("Ширина инспектора"))
                        inspector.frame(width: inspectorSize)
                    }.frame(width: inspectorSize + 8)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }.clipped()
        }
    }
    private var archiveHeader: some View {
        HStack(alignment: .center, spacing: 17) {
            Image(systemName: "doc.zipper").font(.system(size: 35, weight: .light)).foregroundStyle(accent)
                .frame(width: 62, height: 72).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 7) {
                Text(model.displayName).font(.system(size: 24, weight: .semibold)).tracking(-0.6).lineLimit(1)
                    .truncationMode(.middle)
                Text(model.archive?.deletingLastPathComponent().path ?? "").font(.system(size: 11)).foregroundStyle(
                    .secondary
                ).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 18) {
                    Text(fileCount(model.info?.fileCount ?? 0))
                    Text(bytes(model.info?.archiveBytes ?? 0))
                    if let volumes = model.info?.volumes { Text(L("Частей: %@", String(describing: (volumes.count)))) }
                    if model.info?.encrypted == true { Label(L("Защищён"), systemImage: "lock") }
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 26).padding(.vertical, 24)
    }
    private var browserToolbar: some View {
        HStack(spacing: 8) {
            Button {
                model.navigate("")
            } label: {
                Image(systemName: "archivebox")
            }.help(L("Корень архива"))
            ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { index, component in
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                Button(component) { model.navigate(model.breadcrumbs.prefix(index + 1).joined(separator: "/")) }
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Поиск в архиве"), text: $model.query).textFieldStyle(.plain).focused($searchFocused)
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }.padding(.horizontal, 9).padding(.vertical, 7).frame(width: 190)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 18).frame(height: 52)
    }
    private var fileTable: some View {
        Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn(L("Имя"), value: \.name) { row in
                fileName(row)
            }.width(min: 190, ideal: 340)
            TableColumn(L("Размер"), value: \.size) { row in
                Text(row.directory ? "" : bytes(row.size)).foregroundStyle(.secondary).monospacedDigit()
            }.width(85)
            TableColumn(L("Изменён"), value: \.modified) { row in
                Text(String(row.modified.prefix(10))).font(.system(size: 11)).foregroundStyle(.secondary)
                    .monospacedDigit()
            }.width(88)
        }
        .contextMenu(forSelectionType: String.self) { selection in
            if !selection.isEmpty {
                Button(L("Распаковать выбранное…")) { model.extract(selected: true) }.disabled(model.busy)
                Button(L("Быстрый просмотр")) { model.preview() }.disabled(
                    model.selectedRow?.directory != false || model.busy)
                Button(L("Скопировать путь")) { model.copy(selection.sorted().joined(separator: "\n")) }
            }
        } primaryAction: { selection in
            if let path = selection.first, let row = model.rows.first(where: { $0.path == path }) {
                model.activate(row)
            }
        }
        .overlay {
            if model.rows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: model.query.isEmpty ? "folder" : "magnifyingglass").font(
                        .system(size: 28, weight: .light)
                    ).foregroundStyle(.tertiary)
                    Text(model.query.isEmpty ? L("Здесь пока пусто") : L("Ничего не найдено")).foregroundStyle(
                        .secondary)
                }
            }
        }
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.selectedRow == nil ? L("ОБ АРХИВЕ") : L("ВЫБРАНО"))
                .font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary).padding(
                    .bottom, 27)
            if let row = model.selectedRow {
                Image(systemName: row.symbol).font(.system(size: 35, weight: .light)).foregroundStyle(accent).padding(
                    .bottom, 18)
                Text(
                    model.selection.count > 1 ? L("%@ объектов", String(describing: (model.selection.count))) : row.name
                ).font(.system(size: 14, weight: .medium)).lineLimit(3).textSelection(.enabled)
                Text(row.directory ? L("Папка") : bytes(row.size)).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.top, 8)
                Divider().padding(.vertical, 22)
                Text(row.path).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(6)
                Button {
                    model.extract(selected: true)
                } label: {
                    Label(L("Распаковать"), systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.bordered).padding(.top, 24).disabled(model.busy)
                if !row.directory && model.selection.count == 1 {
                    Button(L("Быстрый просмотр"), action: model.preview).buttonStyle(.link).font(.system(size: 11))
                        .padding(.top, 12).disabled(model.busy)
                }
            } else if let info = model.info {
                metric(L("В архиве"), bytes(info.archiveBytes))
                metric(L("После распаковки"), info.unpackedSizeKnown ? bytes(info.unpackedBytes) : L("Неизвестно"))
                metric(L("Файлов"), "\(info.fileCount)")
                Divider().padding(.bottom, 22)
                Label(L("Твои файлы остаются\nна этом компьютере."), systemImage: "internaldrive")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }
            Spacer()
        }.padding(22).frame(maxHeight: .infinity).background(Color.primary.opacity(0.018))
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 21, weight: .medium)).monospacedDigit().tracking(-0.5)
        }.padding(.bottom, 25)
    }
    private var statusbar: some View {
        Group {
            if model.busy, let started = model.operationStarted {
                OperationStatus(
                    title: model.status, target: model.operationTarget, started: started, cancelling: model.cancelling,
                    cancel: model.cancel
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                idleStatusbar.transition(.opacity)
            }
        }
    }
    private var idleStatusbar: some View {
        HStack(spacing: 10) {
            Image(systemName: model.statusIcon).foregroundStyle(.secondary)
            Text(model.status).lineLimit(1)
            Spacer()
            if let result = model.resultURL {
                Button(L("Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([result]) }.buttonStyle(
                    .link)
            } else if !model.selection.isEmpty {
                Text(L("Выбрано: %@", String(describing: (model.selection.count)))).foregroundStyle(.secondary)
            }
        }.font(.system(size: 11)).padding(.horizontal, 23).frame(height: 40)
    }
    private var passwordSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "lock").font(.system(size: 28, weight: .light)).foregroundStyle(accent)
            Text(L("Архив защищён")).font(.title2.weight(.semibold))
            Text(L("Введи пароль для %@.", String(describing: (model.archive?.lastPathComponent ?? L("архива")))))
                .foregroundStyle(.secondary).font(.system(size: 12))
            SecureField(L("Пароль"), text: $model.passwordInput).textFieldStyle(.roundedBorder).onSubmit {
                model.unlock()
            }
            HStack {
                Button(L("Отмена"), action: model.cancelPassword).keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Открыть"), action: model.unlock).buttonStyle(.borderedProminent).keyboardShortcut(
                    .defaultAction)
            }
        }.padding(30).frame(width: 390).tint(accent)
    }
    private func fileName(_ row: BrowserRow) -> some View {
        HStack(spacing: 9) {
            Image(systemName: row.symbol).font(.system(size: 15, weight: .regular)).foregroundStyle(
                row.directory ? accent : Color.secondary
            ).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).lineLimit(1)
                if !model.query.isEmpty {
                    Text(row.path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if row.encrypted {
                Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }

}

struct FilePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = url as NSURL
        view.autostarts = false
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }

}
