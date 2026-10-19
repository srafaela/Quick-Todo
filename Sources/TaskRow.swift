import SwiftUI

private struct CompletionJiggle: GeometryEffect {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(progress * .pi * 4) * 1.5 * (1 - progress)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

struct TaskRow: View {
    let item: TodoItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var jiggleProgress: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                item.done ? Color.accentColor : Color.secondary.opacity(0.6),
                                lineWidth: 1.5
                            )
                        Circle()
                            .fill(Color.accentColor)
                            .scaleEffect(item.done ? 1 : 0.01)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .opacity(item.done ? 1 : 0)
                    }
                    .frame(width: 18, height: 18)
                    .animation(.easeOut(duration: 0.18), value: item.done)

                    Text(item.text)
                        .font(.system(size: 15))
                        .foregroundColor(item.done ? .secondary : .primary)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary)
                                .frame(height: 1.5)
                                .scaleEffect(x: item.done ? 1 : 0, anchor: .leading)
                                .animation(
                                    item.done
                                        ? .easeInOut(duration: 0.25).delay(0.12)
                                        : .easeOut(duration: 0.15),
                                    value: item.done
                                )
                        }
                        .opacity(item.done ? 0.55 : 1)
                        .modifier(CompletionJiggle(progress: jiggleProgress))

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Mark \(item.text) incomplete" : "Complete \(item.text)")

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete task")
                .accessibilityLabel("Delete \(item.text)")
                .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onChange(of: item.done) { _, isDone in
            jiggleProgress = 0
            if isDone {
                withAnimation(.linear(duration: 0.35).delay(0.38)) {
                    jiggleProgress = 1
                }
            }
        }
    }
}
