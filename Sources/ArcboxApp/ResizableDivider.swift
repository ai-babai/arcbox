import AppKit
import ArcboxCore
import SwiftUI

struct ResizableDivider: View {
    @Binding var width: Double
    let actualWidth: CGFloat
    let bounds: ClosedRange<CGFloat>
    let defaultWidth: Double
    let direction: CGFloat
    let label: String
    @State private var dragStart: CGFloat?
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func resize(_ value: CGFloat) {
        width = Double(min(bounds.upperBound, max(bounds.lowerBound, value)))
    }
    var body: some View {
        Rectangle().fill(hovering ? accent.opacity(0.65) : Color(nsColor: .separatorColor))
            .frame(width: 1).frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                guard hovering != inside else { return }
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if hovering {
                    hovering = false
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragStart == nil { dragStart = actualWidth }
                        resize((dragStart ?? actualWidth) + direction * value.translation.width)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { resize(CGFloat(defaultWidth)) }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(Text("\(Int(actualWidth))"))
            .accessibilityAdjustableAction { action in
                switch action {
                case .increment: resize(actualWidth + 16)
                case .decrement: resize(actualWidth - 16)
                @unknown default: break
                }
            }
            .help(L("Потяни, чтобы изменить ширину. Двойной щелчок — сброс."))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
