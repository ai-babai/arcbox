import ArcboxCore
import SwiftUI

private struct CreateContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct CreateSheet: View {
    @ObservedObject var model: ArchiveModel
    @State private var format = "zip"
    @State private var level = 5
    @State private var encrypted = false
    @State private var password = ""
    @State private var divided = false
    @State private var partIndex = 1.0
    @State private var customPartSize = false
    @State private var customMiB = "100"
    @State private var contentHeight: CGFloat = 280
    @FocusState private var passwordFocused: Bool
    private let sizes = [10, 100, 500, 1024, 2048, 4096]
    private var usesParts: Bool { divided || format == "parts" }
    private var supportsPassword: Bool { format == "zip" || format == "7z" }
    private var maximumContentHeight: CGFloat {
        let screenHeight = NSApp.keyWindow?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 700
        return max(180, min(480, screenHeight - 220))
    }
    private var partBytes: Int64? {
        guard usesParts else { return nil }
        let (value, overflow) = Int64(customPartSize ? (Int(customMiB) ?? 0) : sizes[Int(partIndex)])
            .multipliedReportingOverflow(by: 1024 * 1024)
        return overflow ? 0 : value
    }
    private var invalid: Bool {
        model.createInputs.isEmpty || (usesParts && (partBytes ?? 0) <= 0)
            || (supportsPassword && encrypted && password.isEmpty)
            || (format == "parts"
                && (model.createInputs.count != 1 || model.createInputs.first?.hasDirectoryPath == true))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("Создать архив")).font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                Spacer()
                Image(systemName: "archivebox").font(.system(size: 25, weight: .light)).foregroundStyle(accent)
            }
            ScrollView {
                form.padding(2).padding(.bottom, 4)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: CreateContentHeight.self, value: proxy.size.height)
                        })
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, maximumContentHeight))
            .onPreferenceChange(CreateContentHeight.self) { height in
                if height > 0 { contentHeight = ceil(height) }
            }
            Divider()
            HStack {
                Button(L("Отмена")) { model.showCreate = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Создать…")) {
                    model.create(
                        format: format, level: supportsPassword ? level : 0,
                        password: supportsPassword && encrypted ? password : "", partBytes: partBytes)
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(invalid)
            }
        }.font(.system(size: 13)).padding(24).frame(width: 540).tint(accent)
            .dropDestination(for: URL.self) { urls, _ in
                model.createInputs = urls
                return !urls.isEmpty
            }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("Файлы и папки")).fontWeight(.medium)
                    if !model.createInputs.isEmpty {
                        Text("\(model.createInputs.count)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Выбрать…"), action: model.chooseInputs)
                }
                if model.createInputs.isEmpty {
                    Text(L("Выбери файлы или перетащи их сюда."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(model.createInputs.prefix(2), id: \.path) { url in
                            Label(url.lastPathComponent, systemImage: url.hasDirectoryPath ? "folder" : "doc")
                                .lineLimit(1).truncationMode(.middle).help(url.path)
                        }
                        if model.createInputs.count > 2 {
                            Text(L("Ещё объектов: %@", String(model.createInputs.count - 2)))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("Формат результата")).fontWeight(.medium)
                    Picker(L("Формат результата"), selection: $format) {
                        Text("ZIP").tag("zip")
                        Text("7z").tag("7z")
                        Text("TAR").tag("tar")
                        Divider()
                        Text(L("Части исходного файла (.001)")).tag("parts")
                    }.labelsHidden()
                }.frame(maxWidth: .infinity)
                if supportsPassword {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L("Сжатие")).fontWeight(.medium)
                        Picker(L("Сжатие"), selection: $level) {
                            Text(L("Быстрее")).tag(1)
                            Text(L("Баланс")).tag(5)
                            Text(L("Меньше размер")).tag(9)
                        }.labelsHidden()
                    }.frame(maxWidth: .infinity)
                }
            }
            if format == "parts" {
                Text(L("Один файл без упаковки. При распаковке частей восстановится оригинал."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.createInputs.count > 1 || model.createInputs.first?.hasDirectoryPath == true {
                    Text(
                        L(
                            "Для этого режима выбери один файл. Для папок и нескольких файлов используй ZIP или 7z с разбиением."
                        )
                    )
                    .font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            passwordOptions
            partsOptions
        }
    }
    @ViewBuilder private var passwordOptions: some View {
        if supportsPassword {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 18) {
                    Toggle(L("Защитить паролем"), isOn: $encrypted).frame(maxWidth: .infinity, alignment: .leading)
                    if encrypted {
                        SecureField(L("Пароль"), text: $password).textFieldStyle(.roundedBorder)
                            .focused($passwordFocused).frame(maxWidth: .infinity)
                    }
                }.onChange(of: encrypted) { _, enabled in passwordFocused = enabled }
                if encrypted {
                    Text(
                        format == "zip"
                            ? L("AES-256. Нужен архиватор с поддержкой AES ZIP.")
                            : L("Будут зашифрованы содержимое и имена файлов.")
                    )
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
                        horizontal: false, vertical: true)
                }
            }
        }
    }

    private var partsOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if format != "parts" { Toggle(L("Разделить на части"), isOn: $divided) }
            if usesParts {
                HStack {
                    Text(L("Размер каждой части")).fontWeight(.medium)
                    Spacer()
                    Text(bytes(partBytes ?? 0)).monospacedDigit().foregroundStyle(.secondary)
                }
                VStack(spacing: 3) {
                    Slider(value: $partIndex, in: 0...5, step: 1)
                        .accessibilityLabel(L("Размер каждой части"))
                        .accessibilityValue(bytes(Int64(sizes[Int(partIndex)]) * 1024 * 1024))
                        .disabled(customPartSize)
                    HStack(spacing: 0) {
                        ForEach(sizes.indices, id: \.self) { index in
                            Button {
                                partIndex = Double(index)
                                customPartSize = false
                            } label: {
                                Text(bytes(Int64(sizes[index]) * 1024 * 1024))
                                    .font(
                                        .system(
                                            size: 10,
                                            weight: Int(partIndex) == index && !customPartSize
                                                ? .semibold : .regular)
                                    )
                                    .foregroundStyle(
                                        Int(partIndex) == index && !customPartSize ? accent : .secondary
                                    )
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Toggle(L("Свой размер"), isOn: $customPartSize)
                        .onChange(of: customPartSize) { _, enabled in
                            if enabled { customMiB = String(sizes[Int(partIndex)]) }
                        }
                    Spacer()
                    if customPartSize {
                        TextField(L("Размер"), text: $customMiB).textFieldStyle(.roundedBorder).frame(width: 86)
                        Text(L("МБ")).foregroundStyle(.secondary)
                    }
                }
                Text(L("Все части сохранятся в одной папке. Последняя может быть меньше."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
                        horizontal: false, vertical: true)
            }
        }
    }

}
