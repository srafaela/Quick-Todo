import Foundation
import Combine

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var done = false
}

final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = [] {
        didSet { save() }
    }
    @Published private(set) var storageError: String?

    private let defaults: UserDefaults
    private let storageKey = "quicktodo.items"
    private var canSave = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            items = try JSONDecoder().decode([TodoItem].self, from: data)
        } catch {
            // Keep the original data untouched until the user chooses to reset it.
            canSave = false
            storageError = "Saved tasks couldn't be read. Your existing data hasn't been changed."
            NSLog("QuickTodo: Failed to load tasks: %@", error.localizedDescription)
        }
    }

    func add(_ text: String) {
        guard canSave else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(TodoItem(text: trimmed), at: 0)
    }

    func toggle(_ item: TodoItem) {
        guard canSave, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].done.toggle()
    }

    func delete(_ item: TodoItem) {
        guard canSave else { return }
        items.removeAll { $0.id == item.id }
    }

    func clearCompleted() {
        guard canSave else { return }
        items.removeAll { $0.done }
    }

    func resetSavedTasks() {
        // Avoid saving an empty array while removing the stored data.
        canSave = false
        items.removeAll()
        defaults.removeObject(forKey: storageKey)
        storageError = nil
        canSave = true
    }

    private func save() {
        guard canSave else { return }
        do {
            defaults.set(try JSONEncoder().encode(items), forKey: storageKey)
            storageError = nil
        } catch {
            storageError = "Tasks couldn't be saved. Changes may be lost when you quit."
            NSLog("QuickTodo: Failed to save tasks: %@", error.localizedDescription)
        }
    }
}
