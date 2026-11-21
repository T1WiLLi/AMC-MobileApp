import SwiftUI

/// Onglet recherche (`Tab(role: .search)`), commun aux deux portails (RQ-042).
struct SearchScreen: View {
    var prompt: LocalizedStringKey = "Riz, farine, œufs…"
    var emptyTitle = "Chercher un produit"
    var emptyMessage: LocalizedStringKey = "Riz, farine, œufs, lentilles… La recherche arrive avec l'épic E05."

    @State private var query = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                query.isEmpty ? emptyTitle : "Aucun résultat pour « \(query) »",
                systemImage: "magnifyingglass",
                description: Text(emptyMessage)
            )
            .navigationTitle("Recherche")
            .profileToolbar()
        }
        .searchable(text: $query, prompt: prompt)
    }
}

#Preview("Clair") {
    SearchScreen()
}

#Preview("Vendeur sombre") {
    SearchScreen(prompt: "Produit ou quartier", emptyTitle: "Chercher la demande", emptyMessage: "Un produit ou un quartier : vois qui le veut.")
        .preferredColorScheme(.dark)
}
