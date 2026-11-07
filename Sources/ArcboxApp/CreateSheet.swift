import SwiftUI
import ArcboxCore

struct CreateSheet: View {
    @ObservedObject var model: ArchiveModel
    @State private var format = "zip"
    @State private var level = 5
    @State private var password = ""
    @State private var divided = false
    @State private var partIndex = 1.0
    @State private var customPartSize = false
    @State private var customMiB = "100"
    private let sizes = [10, 100, 500, 1024, 2048, 4096]
    private var usesParts: Bool { divided || format == "parts" }
    private var partBytes: Int64? {
        guard usesParts else { return nil }
        let (value, overflow) = Int64(customPartSize ? (Int(customMiB) ?? 0) : sizes[Int(partIndex)]).multipliedReportingOverflow(by: 1024 * 1024)
        return overflow ? 0 : value
    }
    private var invalid: Bool {
        model.createInputs.isEmpty || (usesParts && (partBytes ?? 0) <= 0) ||
        (format == "parts" && (model.createInputs.count != 1 || model.createInputs.first?.hasDirectoryPath == true))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L("Создать архив")).font(.system(size: 25, weight: .semibold)).tracking(-0.6)
                Spacer()
                Image(systemName: "archivebox").font(.system(size: 28, weight: .light)).foregroundStyle(accent)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(L("Файлы и папки")).fontWeight(.medium); Spacer(); Button(L("Выбрать…"), action: model.chooseInputs) }
                        if model.createInputs.isEmpty {
                            Text(L("Выбери файлы или перетащи их сюда.")).font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 14)
                        } else {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(model.createInputs.prefix(4), id: \.path) { url in
                                    Label(url.lastPathComponent, systemImage: url.hasDirectoryPath ? "folder" : "doc").lineLimit(1)
                                }
                                if model.createInputs.count > 4 { Text(L("Ещё объектов: %@", String(describing: (model.createInputs.count - 4)))).foregroundStyle(.secondary) }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Формат результата")).fontWeight(.medium)
                        Picker(L("Формат результата"), selection: $format) {
                            Text("ZIP").tag("zip"); Text("7z").tag("7z"); Text("TAR").tag("tar")
                            Divider()
                            Text(L("Части исходного файла (.001)")).tag("parts")
                        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                        if format == "parts" {
                            Text(L("Один файл без упаковки. При распаковке частей восстановится оригинал.")).font(.system(size: 11)).foregroundStyle(.secondary)
                            if model.createInputs.count > 1 || model.createInputs.first?.hasDirectoryPath == true {
                                Text(L("Для этого режима выбери один файл. Для папок и нескольких файлов используй ZIP или 7z с разбиением.")).font(.system(size: 11)).foregroundStyle(.red)
                            }
                        }
                    }
                    if format == "zip" || format == "7z" {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Сжатие")).fontWeight(.medium)
                            Picker(L("Сжатие"), selection: $level) { Text(L("Быстрее")).tag(1); Text(L("Баланс")).tag(5); Text(L("Меньше размер")).tag(9) }.pickerStyle(.segmented).labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Пароль")).fontWeight(.medium)
                            SecureField(L("Необязательно"), text: $password).textFieldStyle(.roundedBorder)
                            if !password.isEmpty {
                                Text(format == "zip" ? L("AES-256. Нужен архиватор с поддержкой AES ZIP.") : L("Будут зашифрованы содержимое и имена файлов.")).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        if format != "parts" { Toggle(L("Разделить на части"), isOn: $divided) }
                        if usesParts {
                            HStack {
                                Text(L("Размер каждой части")).fontWeight(.medium)
                                Spacer()
                                Text(bytes(partBytes ?? 0)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Slider(value: $partIndex, in: 0...5, step: 1)
                                .accessibilityLabel(L("Размер каждой части"))
                                .accessibilityValue(bytes(Int64(sizes[Int(partIndex)]) * 1024 * 1024))
                                .disabled(customPartSize)
                            HStack(spacing: 0) {
                                ForEach(sizes.indices, id: \.self) { index in
                                    Button { partIndex = Double(index); customPartSize = false } label: {
                                        Text(bytes(Int64(sizes[index]) * 1024 * 1024))
                                            .font(.system(size: 10, weight: Int(partIndex) == index && !customPartSize ? .semibold : .regular))
                                            .foregroundStyle(Int(partIndex) == index && !customPartSize ? accent : .secondary)
                                            .frame(maxWidth: .infinity)
                                    }.buttonStyle(.plain)
                                }
                            }
                            Toggle(L("Свой размер"), isOn: $customPartSize).font(.system(size: 12))
                                .onChange(of: customPartSize) { _, enabled in
                                    if enabled { customMiB = String(sizes[Int(partIndex)]) }
                                }
                            if customPartSize { HStack { TextField(L("Размер"), text: $customMiB).textFieldStyle(.roundedBorder).frame(width: 110); Text(L("МБ")).foregroundStyle(.secondary) } }
                            Text(L("Все части сохранятся в одной папке. Последняя может быть меньше.")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.trailing, 8)
            }.frame(height: format == "parts" ? 300 : format == "tar" ? (usesParts ? 340 : 245) : (usesParts ? 450 : 365))
            Divider()
            HStack {
                Button(L("Отмена")) { model.showCreate = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Создать…")) {
                    model.create(format: format, level: format == "tar" || format == "parts" ? 0 : level, password: format == "zip" || format == "7z" ? password : "", partBytes: partBytes)
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(invalid)
            }
        }.font(.system(size: 13)).padding(28).frame(width: 480).tint(accent)
            .dropDestination(for: URL.self) { urls, _ in model.createInputs = urls; return !urls.isEmpty }
    }
}
