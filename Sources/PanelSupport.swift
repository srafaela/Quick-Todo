import Cocoa
import SwiftUI

enum SlideEdge: String, CaseIterable {
    case top, bottom, left, right

    var title: String { rawValue.capitalized }
}

extension Notification.Name {
    static let quickTodoFocusInput = Notification.Name("quicktodo.focus")
}

// NSVisualEffectView normally intercepts clicks intended for the SwiftUI controls.
final class PassthroughEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassthroughEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// Makes the initial click work even while the menu bar app is inactive.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
