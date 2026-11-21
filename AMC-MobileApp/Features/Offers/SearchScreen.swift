import SwiftUI

/// Onglet recherche (`Tab(role: .search)`) : recherche de produits et de lots (RQ-042).
struct SearchScreen: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                query.isEmpty ? "Chercher un produit" : "Aucun résultat pour « \(query) »",
                systemImage: "magnifyingglass",
                description: Text("Riz, farine, œufs, lentilles… La recherche arrive avec l'épic E05.")
            )
            .navigationTitle("Recherche")
            .profileToolbar()
        }
        .searchable(text: $query, prompt: "Riz, farine, œufs…")
    }
}

#Preview("Clair") {
    SearchScreen()
}

#Preview("Sombre") {
    SearchScreen()
        .preferredColorScheme(.dark)
}
