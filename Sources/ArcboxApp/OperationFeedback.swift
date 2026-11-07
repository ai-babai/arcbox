import ArcboxCore
import SwiftUI

struct OperationStatus: View {
    let title: String
    let target: String?
    let started: Date
    let cancelling: Bool
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.system(size: 18, weight: .light)).foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(target ?? L("Исходные файлы остаются на месте."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 12)
                TimelineView(.periodic(from: started, by: 1)) { context in
                    let elapsed = max(0, Int(context.date.timeIntervalSince(started)))
                    let formatted = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
                    Text(formatted)
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityLabel(L("Прошло времени"))
                        .accessibilityValue(formatted)
                }
                Button(L("Отмена"), action: cancel).controlSize(.small).disabled(cancelling)
            }
            ProgressView().progressViewStyle(.linear).tint(accent).frame(height: 3)
                .accessibilityLabel(title)
        }.padding(.horizontal, 20).padding(.vertical, 12)
            .background(accent.opacity(0.035))
    }
}

struct ArchiveLoading: View {
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var placeholders: some View {
        VStack(spacing: 14) {
            ForEach(0..<6) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 22, height: 22)
                    RoundedRectangle(cornerRadius: 4).frame(width: index.isMultiple(of: 2) ? 220 : 160, height: 11)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4).frame(width: 64, height: 11)
                }.frame(height: 30)
            }
        }.foregroundStyle(Color.primary.opacity(0.09)).accessibilityHidden(true)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 16) {
                Image(systemName: "doc.zipper").font(.system(size: 34, weight: .light)).foregroundStyle(accent)
                Text(name).font(.system(size: 23, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            }
            Divider()
            if reduceMotion {
                placeholders
            } else {
                placeholders.phaseAnimator([false, true]) { content, phase in
                    content.opacity(phase ? 1 : 0.35)
                } animation: { _ in
                    .easeInOut(duration: 1.1)
                }
            }
            Spacer(minLength: 0)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
