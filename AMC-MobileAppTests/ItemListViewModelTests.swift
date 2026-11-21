import Testing
@testable import AMC_MobileApp

@MainActor
struct ItemListViewModelTests {
    struct StubService: ItemService {
        let items: [Item]
        func fetchItems() async throws -> [Item] { items }
    }

    @Test func loadPopulatesItems() async {
        let vm = ItemListViewModel(service: StubService(items: [Item(title: "A")]))
        await vm.load()
        #expect(vm.items.count == 1)
        #expect(vm.state == .loaded)
    }

    @Test func addItemIgnoresBlankTitle() {
        let vm = ItemListViewModel(service: StubService(items: []))
        vm.newItemTitle = "   "
        vm.addItem()
        #expect(vm.items.isEmpty)
    }

    @Test func toggleFlipsDone() {
        let vm = ItemListViewModel(service: StubService(items: []))
        vm.newItemTitle = "Tâche"
        vm.addItem()
        vm.toggle(vm.items[0])
        #expect(vm.items[0].isDone)
    }
}
