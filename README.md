# QuickTodo <img width="30" height="30 " alt="icon" src="https://github.com/user-attachments/assets/47a7624b-17b7-4480-ad1f-6433c2dc5581" />

QuickTodo is a small, keyboard-first task list for macOS. It runs from the menu bar, opens with **Option + Space**, and can slide in from any edge of the screen.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools (`xcode-select --install`)

## Build

```bash
chmod +x build.sh
./build.sh
```

The script creates `QuickTodo.app` and `QuickTodo-macOS.zip` next to the source code. Both are built for the architecture of the Mac running the script.

To build a universal release for both Apple Silicon and Intel Macs:

```bash
./build.sh --universal
```

## Use

- Press **Option + Space** to show or hide the task list.
- Type a task and press **Return** to add it.
- Click a task to mark it complete or incomplete.
- Hover over a task to reveal the delete button.
- Use **Clear completed** to delete finished tasks.
- Choose the slide-in edge from the menu bar icon. If the panel is open, it slides directly to the new position without closing; your choice is saved for next time.
- Choose **Reset QuickTodo…** from the menu bar icon to delete every task and restore the default **Top** position. A confirmation dialog appears independently of the slide-in panel, so closing the panel cannot hide it.

If Option + Space is already reserved by another app, QuickTodo displays a shortcut warning in its menu. You can still open it from the menu bar.

Tasks are stored locally using `UserDefaults` under the existing `quicktodo.items` key. This keeps data from older builds when the bundle identifier remains `local.quicktodo`. There are no accounts or network requests. Reset QuickTodo removes the stored tasks and slide-in edge preference (`quicktodo.edge`). It does not uninstall the app.

> [!WARNING]
> **macOS security:** the build script uses ad-hoc signing. It does **not** notarize the application. Downloaded copies may trigger Gatekeeper warnings, and some managed Macs may block them. For frictionless public distribution, sign with an Apple Developer ID and notarize the app before publishing the release.

## Project layout

```text
main.swift                App entry point
Sources/AppDelegate.swift Menu bar, global hotkey, panel animation
Sources/ContentView.swift Task list and UI
Sources/TaskRow.swift     Task row and completion animation
Sources/PanelSupport.swift Shared panel and visual-effect helpers
Sources/TodoStore.swift   Task model and local persistence
build.sh                  Compile, sign, and archive
```
