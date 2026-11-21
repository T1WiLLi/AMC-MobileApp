import SwiftUI

struct ItemListView: View {
    @State var viewModel: ItemListViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Nouvel élément", text: $viewModel.newItemTitle)
                            .onSubmit(viewModel.addItem)
                        Button("Ajouter", systemImage: "plus.circle.fill", action: viewModel.addItem)
                            .labelStyle(.iconOnly)
                            .disabled(!viewModel.canAddItem)
                    }
                }

                Section {
                    ForEach(viewModel.items) { item in
                        ItemRow(item: item) { viewModel.toggle(item) }
                    }
                    .onDelete(perform: viewModel.delete)
                }
            }
            .overlay {
                switch viewModel.state {
                case .loading:
                    ProgressView()
                case .failed(let message):
                    ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(message))
                default:
                    EmptyView()
                }
            }
            .navigationTitle("Éléments")
            .task { await viewModel.load() }
        }
    }
}

private struct ItemRow: View {
    let item: Item
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Label {
                Text(item.title)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
            } icon: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
            }
        }
        .tint(.primary)
    }
}

#Preview {
    ItemListView(viewModel: ItemListViewModel(service: InMemoryItemService()))
}
