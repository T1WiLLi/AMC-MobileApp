import SwiftUI

@main
struct AMCMobileApp: App {
    var body: some Scene {
        WindowGroup {
            ItemListView(viewModel: ItemListViewModel(service: InMemoryItemService()))
        }
    }
}
