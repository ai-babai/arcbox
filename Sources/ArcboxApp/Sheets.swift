import SwiftUI
import ArcboxCore

struct AgentSheet: View {
    @ObservedObject var model: ArchiveModel
    @State private var tab = 0
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Тот же Arcbox. Через команды.")).font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                    Text(L("Архивы, разбиение файлов и сборка частей.")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "terminal").font(.system(size: 28, weight: .light)).foregroundStyle(accent)
            }
            Picker(L("Интерфейс"), selection: $tab) { Text(L("Командная строка")).tag(0); Text(L("MCP для агента")).tag(1) }.pickerStyle(.segmented)
            ScrollView {
                Text(tab == 0 ? model.listCommand : model.mcpConfiguration)
                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }.frame(height: 170).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            Text(tab == 0 ? L("CLI возвращает JSON и код завершения. Полный список команд: arcbox --help. Для паролей используй --password-stdin.") : L("Добавь эту конфигурацию в MCP-клиент. Сервер запускается локально и предоставляет шесть инструментов arcbox_*."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            HStack {
                Button(L("Готово")) { model.showAgent = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(copied ? L("Скопировано") : L("Скопировать")) {
                    model.copy(tab == 0 ? model.listCommand : model.mcpConfiguration); copied = true
                }.buttonStyle(.borderedProminent)
            }
        }.padding(30).frame(width: 590).tint(accent).onChange(of: tab) { _, _ in copied = false }
    }
}
