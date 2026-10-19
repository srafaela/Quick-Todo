import Cocoa
import SwiftUI

private struct BubbleShape: Shape {
    var tailInset: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 6
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tail)
        var path = Path(roundedRect: body, cornerRadius: 8, style: .continuous)
        let x = rect.maxX - tailInset
        path.move(to: CGPoint(x: x - tail, y: body.maxY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        path.addLine(to: CGPoint(x: x + tail, y: body.maxY))
        path.closeSubpath()
        return path
    }
}

private struct HintBubble: View {
    var body: some View {
        Text("Options are in the menu bar icon at the top of your screen")
            .font(.system(size: 11))
            .multilineTextAlignment(.leading)
            .frame(width: 190, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 13)
            .background(.regularMaterial, in: BubbleShape())
            .overlay(BubbleShape().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .allowsHitTesting(false)
    }
}

struct ContentView: View {
    @ObservedObject var store: TodoStore

    @State private var draft = ""
    @State private var showHint = false
    @State private var confirmingReset = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .foregroundColor(.secondary)
                TextField("New task…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($inputFocused)
                    .disabled(store.storageError != nil)
                    .onSubmit {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            store.add(draft)
                        }
                        draft = ""
                    }
            }

            Divider()

            if let storageError = store.storageError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(storageError, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Button("Reset saved tasks…") { confirmingReset = true }
                        .font(.system(size: 12))
                }
                .padding(.vertical, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.items) { item in
                        TaskRow(
                            item: item,
                            onToggle: { store.toggle(item) },
                            onDelete: { withAnimation { store.delete(item) } }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .disabled(store.storageError != nil)

            Divider()

            HStack(spacing: 6) {
                if store.items.contains(where: { $0.done }) {
                    Button("Clear completed") {
                        withAnimation { store.clearCompleted() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .disabled(store.storageError != nil)
                }

                Spacer()

                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(showHint ? .primary : .secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) { showHint = hovering }
                    }
                    .help("QuickTodo options")

                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Quit QuickTodo")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottomTrailing) {
            if showHint {
                HintBubble()
                    .padding(.trailing, 30)
                    .padding(.bottom, 42)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomTrailing)))
            }
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onReceive(NotificationCenter.default.publisher(for: .quickTodoFocusInput)) { _ in
            inputFocused = true
        }
        .confirmationDialog(
            "Delete all saved tasks?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Delete saved tasks", role: .destructive) { store.resetSavedTasks() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the locally stored task data. It can't be undone.")
        }
    }
}
