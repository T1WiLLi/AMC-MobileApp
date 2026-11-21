import Foundation

protocol ItemService: Sendable {
    func fetchItems() async throws -> [Item]
}

struct InMemoryItemService: ItemService {
    func fetchItems() async throws -> [Item] {
        [
            Item(title: "Découvrir MVVM"),
            Item(title: "Créer un ViewModel"),
            Item(title: "Écrire des tests", isDone: true),
        ]
    }
}
