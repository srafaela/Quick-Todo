import Cocoa
import Carbon
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let store = TodoStore()
    private let panelSize = NSSize(width: 380, height: 440)
    private let panelMargin: CGFloat = 10
    private let edgePreferenceKey = "quicktodo.edge"

    private var panel: KeyPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var escapeMonitor: Any?
    private var shortcutAvailable = false
    private var resetConfirmationRequested = false
    private var isShowingResetConfirmation = false
    private var isStatusMenuOpen = false
    private var isRestoringFocusAfterMenu = false
    private var pendingEdgeMove = false

    private var isShown = false
    private var wantsToShow = false
    private var isAnimating = false
    private var lastScreen: NSScreen?

    private var edge: SlideEdge {
        get {
            let value = UserDefaults.standard.string(forKey: edgePreferenceKey) ?? ""
            return SlideEdge(rawValue: value) ?? .top
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: edgePreferenceKey)
            if isStatusMenuOpen {
                // Keep the open menu in place while its selection changes.
                statusItem.menu?.items.forEach { item in
                    if let value = item.representedObject as? String,
                       let option = SlideEdge(rawValue: value) {
                        item.state = option == newValue ? .on : .off
                    }
                }
            } else {
                updateMenu()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        configurePanel()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "checklist",
            accessibilityDescription: "QuickTodo"
        )

        registerHotKey()
        updateMenu()

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape), self?.wantsToShow == true {
                self?.setVisible(false)
                return nil
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    private func configureMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit QuickTodo",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    private func configurePanel() {
        panel = KeyPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = FirstClickHostingView(rootView: ContentView(store: store))
    }

    private func updateMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let showTitle = shortcutAvailable ? "Show / Hide   ⌥Space" : "Show / Hide"
        let toggleItem = NSMenuItem(title: showTitle, action: #selector(togglePanel), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        if !shortcutAvailable {
            let warning = NSMenuItem(title: "⌥Space unavailable (shortcut conflict)", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
        }

        menu.addItem(.separator())
        let header = NSMenuItem(title: "Slide in from", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for option in SlideEdge.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(selectEdge(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == edge ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Reset QuickTodo…", action: #selector(confirmReset), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func selectEdge(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selected = SlideEdge(rawValue: rawValue) else { return }
        guard selected != edge else { return }
        edge = selected
        if wantsToShow {
            pendingEdgeMove = true
            movePanelToSelectedEdgeIfNeeded()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isStatusMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isStatusMenuOpen = false
        guard wantsToShow, !resetConfirmationRequested, !isShowingResetConfirmation else { return }

        // Restore key-window status after menu tracking ends. Without this,
        // the panel would remain visible but couldn't detect the next focus loss.
        isRestoringFocusAfterMenu = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.isRestoringFocusAfterMenu = false }
            guard self.wantsToShow, !self.resetConfirmationRequested else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func confirmReset() {
        guard !resetConfirmationRequested, !isShowingResetConfirmation else { return }
        resetConfirmationRequested = true

        // Close the floating panel first. Its dismissal normally hides our app,
        // which would also hide an alert shown during the panel animation.
        setVisible(false)
        DispatchQueue.main.async { [weak self] in
            self?.presentResetConfirmationIfReady()
        }
    }

    private func presentResetConfirmationIfReady() {
        guard resetConfirmationRequested, !isAnimating, !isShown, !wantsToShow else { return }
        resetConfirmationRequested = false
        isShowingResetConfirmation = true

        let alert = NSAlert()
        alert.messageText = "Reset QuickTodo?"
        alert.informativeText = "This permanently deletes all tasks and restores the slide-in position to Top. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset QuickTodo")
        alert.addButton(withTitle: "Cancel")

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        isShowingResetConfirmation = false

        if confirmed {
            store.resetSavedTasks()
            UserDefaults.standard.removeObject(forKey: edgePreferenceKey)
            updateMenu()
        }

        if !wantsToShow, NSApp.isActive {
            NSApp.hide(nil)
        }
    }

    private func registerHotKey() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak delegate] in delegate?.togglePanel() }
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )

        guard handlerStatus == noErr else {
            NSLog("QuickTodo: Couldn't install hotkey handler (status %d)", handlerStatus)
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5154444F), id: 1)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        if registrationStatus == noErr {
            shortcutAvailable = true
        } else {
            NSLog("QuickTodo: Option+Space couldn't be registered (status %d)", registrationStatus)
            if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
            hotKeyHandler = nil
        }
    }

    @objc private func togglePanel() {
        guard !resetConfirmationRequested, !isShowingResetConfirmation else { return }
        setVisible(!wantsToShow)
    }

    private func setVisible(_ visible: Bool) {
        wantsToShow = visible
        if !visible { pendingEdgeMove = false }
        guard !isAnimating, isShown != visible else { return }
        if visible { showPanel() } else { hidePanel() }
    }

    private func frames(on screen: NSScreen) -> (shown: NSRect, hidden: NSRect) {
        let visible = screen.visibleFrame
        let full = screen.frame
        var shown = NSRect(origin: .zero, size: panelSize)
        var hidden = shown

        switch edge {
        case .top:
            shown.origin = NSPoint(x: visible.midX - panelSize.width / 2,
                                   y: visible.maxY - panelSize.height - panelMargin)
            hidden.origin = NSPoint(x: shown.minX, y: full.maxY + 4)
        case .bottom:
            shown.origin = NSPoint(x: visible.midX - panelSize.width / 2,
                                   y: visible.minY + panelMargin)
            hidden.origin = NSPoint(x: shown.minX, y: full.minY - panelSize.height - 4)
        case .left:
            shown.origin = NSPoint(x: visible.minX + panelMargin,
                                   y: visible.midY - panelSize.height / 2)
            hidden.origin = NSPoint(x: full.minX - panelSize.width - 4, y: shown.minY)
        case .right:
            shown.origin = NSPoint(x: visible.maxX - panelSize.width - panelMargin,
                                   y: visible.midY - panelSize.height / 2)
            hidden.origin = NSPoint(x: full.maxX + 4, y: shown.minY)
        }
        return (shown, hidden)
    }

    private func showPanel() {
        let mousePosition = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mousePosition) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }

        isAnimating = true
        lastScreen = screen
        let positions = frames(on: screen)
        panel.setFrame(positions.hidden, display: false)
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            panel.animator().setFrame(positions.shown, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.isShown = true
            self.finishAnimation()
            if self.wantsToShow {
                NotificationCenter.default.post(name: .quickTodoFocusInput, object: nil)
            }
        })
    }

    private func hidePanel() {
        isAnimating = true
        let screen = lastScreen ?? panel.screen ?? NSScreen.main
        guard let screen else {
            panel.orderOut(nil)
            isShown = false
            finishAnimation()
            return
        }
        let positions = frames(on: screen)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(positions.hidden, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.isShown = false
            if !self.wantsToShow,
               !self.resetConfirmationRequested,
               !self.isShowingResetConfirmation,
               NSApp.isActive {
                NSApp.hide(nil)
            }
            self.finishAnimation()
        })
    }

    private func movePanelToSelectedEdgeIfNeeded() {
        guard pendingEdgeMove, wantsToShow, isShown, !isAnimating else { return }
        guard let screen = lastScreen ?? panel.screen ?? NSScreen.main else { return }

        pendingEdgeMove = false
        let destination = frames(on: screen).shown
        guard panel.frame != destination else { return }

        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(destination, display: true)
        }, completionHandler: { [weak self] in
            self?.finishAnimation()
        })
    }

    private func finishAnimation() {
        isAnimating = false
        if isShown != wantsToShow {
            setVisible(wantsToShow)
        } else if pendingEdgeMove {
            movePanelToSelectedEdgeIfNeeded()
        }
        if resetConfirmationRequested {
            DispatchQueue.main.async { [weak self] in
                self?.presentResetConfirmationIfReady()
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking the status item also takes focus away from this panel.
        // Defer the check until AppKit has opened the menu so choosing a new
        // edge doesn't dismiss the panel before the move can happen.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsToShow, !self.panel.isKeyWindow else { return }
            guard !self.isStatusMenuOpen, !self.isRestoringFocusAfterMenu else { return }
            self.setVisible(false)
        }
    }
}
