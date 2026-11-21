import Foundation
import Observation

@MainActor
@Observable
final class ItemListViewModel {
    enum State: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private(set) var items: [Item] = []
    private(set) var state: State = .idle
    var newItemTitle = ""

    private let service: ItemService

    init(service: ItemService) {
        self.service = service
    }

    var canAddItem: Bool {
        !newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() async {
        state = .loading
        do {
            items = try await service.fetchItems()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func addItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        items.append(Item(title: title))
        newItemTitle = ""
    }

    func toggle(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isDone.toggle()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.reversed() {
            items.remove(at: index)
        }
    }
}
