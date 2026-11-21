import SwiftUI

/// Onglet recherche (`Tab(role: .search)`), commun aux deux portails (RQ-042).
/// En attendant le branchement sur les dépôts, propose des produits statiques et les filtre localement.
struct SearchScreen: View {
    var prompt: LocalizedStringKey = "Riz, farine, œufs…"
    var emptyTitle = "Suggestions"
    var emptyMessage: LocalizedStringKey = "Des produits d'ici, achetés en gros entre voisins."
    var suggestions: [Suggestion] = Suggestion.catalog

    @State private var query = ""

    private var results: [Suggestion] { Self.filter(suggestions, query: query) }

    var body: some View {
        NavigationStack {
            List {
                if !results.isEmpty {
                    Section {
                        ForEach(results) { SuggestionRow(suggestion: $0) }
                    } header: {
                        Text(query.isEmpty ? emptyTitle : FrenchPlural.count(results.count, "produit"))
                    } footer: {
                        if query.isEmpty { Text(emptyMessage) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grenierBackground()
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView(
                        "Aucun produit trouvé",
                        systemImage: "magnifyingglass",
                        description: Text("Essaie « riz », « farine » ou « lentilles ».")
                    )
                }
            }
            .animation(.smooth, value: results)
            .navigationTitle("Recherche")
            .profileToolbar()
        }
        .searchable(text: $query, prompt: prompt)
    }

    /// Filtre insensible à la casse et aux accents sur le nom, le producteur et la région.
    static func filter(_ suggestions: [Suggestion], query: String) -> [Suggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return suggestions }
        return suggestions.filter {
            $0.name.localizedStandardContains(trimmed)
                || $0.vendor.localizedStandardContains(trimmed)
                || $0.region.localizedStandardContains(trimmed)
        }
    }
}

extension SearchScreen {
    /// Produit proposé tant que la recherche n'est pas branchée sur le catalogue.
    struct Suggestion: Identifiable, Hashable, Sendable {
        var id: String { name }
        let name: String
        let vendor: String
        let region: String
        let category: Product.Category

        static let catalog: [Suggestion] = [
            .init(name: "Riz basmati", vendor: "Ferme Lafleur", region: "Mirabel", category: .grains),
            .init(name: "Farine de blé", vendor: "Les Moulins du Nord", region: "Lanaudière", category: .flour),
            .init(name: "Lentilles corail", vendor: "Coop Agrinord", region: "Abitibi", category: .legumes),
            .init(name: "Pommes Cortland", vendor: "Verger Bilodeau", region: "Saint-Joseph-du-Lac", category: .produce),
            .init(name: "Huile de canola", vendor: "Coop Agrinord", region: "Montérégie", category: .oils),
            .init(name: "Œufs de poules en liberté", vendor: "Ferme Bio-Rive", region: "Saint-Jean-sur-Richelieu", category: .eggs)
        ]
    }

    private struct SuggestionRow: View {
        let suggestion: Suggestion

        var body: some View {
            HStack(spacing: 12) {
                ProductIcon(category: suggestion.category)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.name)
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text("\(suggestion.vendor) · \(suggestion.region)")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
            }
            .padding(.vertical, 2)
            .listRowBackground(Color.surface)
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview("Clair") {
    SearchScreen()
}

#Preview("Sombre") {
    SearchScreen()
        .preferredColorScheme(.dark)
}

#Preview("Vendeur sombre") {
    SearchScreen(prompt: "Produit ou quartier", emptyTitle: "Chercher la demande", emptyMessage: "Un produit ou un quartier : vois qui le veut.")
        .preferredColorScheme(.dark)
}
