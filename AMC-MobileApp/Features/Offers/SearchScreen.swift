import SwiftUI

/// Onglet recherche (`Tab(role: .search)`), commun aux deux portails (RQ-042).
/// Côté Familles (`linksToOffers`), cherche dans les lots actifs des dépôts et ouvre la fiche du lot touché ;
/// sinon (ou tant que rien n'est chargé), propose des produits statiques filtrés localement.
struct SearchScreen: View {
    var prompt: LocalizedStringKey = "Riz, farine, œufs…"
    var emptyTitle = "Suggestions"
    var emptyMessage: LocalizedStringKey = "Des produits d'ici, achetés en gros entre voisins."
    var suggestions: [Suggestion] = Suggestion.catalog
    /// true : les résultats viennent des lots actifs et ouvrent leur fiche (portail Familles).
    var linksToOffers = false

    @Environment(\.appContext) private var context
    @State private var query = ""
    /// Lots actifs chargés depuis les dépôts (nil tant que rien n'est chargé).
    @State private var offerSuggestions: [Suggestion]?
    /// Lot ouvert en feuille. Une feuille plutôt qu'un push : la fiche masque la barre d'onglets, et au retour
    /// l'onglet Recherche réapparaissait sans son champ (barre d'onglets classique, saisie perdue).
    @State private var openedOffer: OfferRoute?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var results: [Suggestion] { Self.filter(offerSuggestions ?? suggestions, query: query) }

    var body: some View {
        NavigationStack {
            List {
                if !results.isEmpty {
                    Section {
                        ForEach(results) { suggestion in
                            if let offerId = suggestion.offerId {
                                Button {
                                    openedOffer = OfferRoute(offerId: offerId)
                                } label: {
                                    HStack {
                                        SuggestionRow(suggestion: suggestion)
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.forward")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                            .accessibilityHidden(true)
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.surface)
                                .accessibilityHint("Ouvre le lot")
                            } else {
                                SuggestionRow(suggestion: suggestion)
                            }
                        }
                    } header: {
                        Label(
                            query.isEmpty ? emptyTitle : FrenchPlural.count(results.count, "produit"),
                            systemImage: query.isEmpty ? "sparkles" : "line.3.horizontal.decrease.circle.fill"
                        )
                        .foregroundStyle(Color.grenier)
                        .symbolRenderingMode(.hierarchical)
                        .contentTransition(.symbolEffect(.replace))
                    } footer: {
                        if query.isEmpty {
                            Label {
                                Text(emptyMessage)
                            } icon: {
                                Image(systemName: "person.3.fill")
                                    .foregroundStyle(Color.grenier)
                            }
                            .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grenierBackground()
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView {
                        VStack(spacing: 12) {
                            StateIllustration(systemImage: "magnifyingglass")
                                .symbolEffect(.wiggle, value: reduceMotion ? "" : query)
                            Text("Aucun produit trouvé")
                                .font(.title2.bold())
                                .foregroundStyle(.texte)
                        }
                    } description: {
                        Text("Essaie un autre produit ou le nom d'un producteur.")
                    } actions: {
                        Button {
                            query = ""
                        } label: {
                            Label("Voir les suggestions", systemImage: "sparkles")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.glass)
                        .tint(.grenier)
                    }
                    .grenierTransition(.cardAppear)
                }
            }
            .grenierAnimation(.smooth, value: results)
            .grenierHaptic(.warning, trigger: results.isEmpty) { _, new in new }
            .navigationTitle("Recherche")
            .profileToolbar()
            .sheet(item: $openedOffer) { route in
                OfferSheet(offerId: route.offerId)
            }
        }
        .searchable(text: $query, prompt: prompt)
        .task {
            guard linksToOffers, offerSuggestions == nil else { return }
            offerSuggestions = await Self.loadOfferSuggestions(from: context.repositories)
        }
    }

    /// Un résultat par lot actif (produit, vendeur, format). nil si rien n'a pu être chargé : on garde le catalogue.
    static func loadOfferSuggestions(from repositories: AppRepositories) async -> [Suggestion]? {
        guard let offers = try? await repositories.offers.activeOffers(inZone: nil), !offers.isEmpty else { return nil }
        var found: [Suggestion] = []
        for offer in offers {
            guard let product = try? await repositories.vendors.product(id: offer.productId),
                  let vendor = try? await repositories.vendors.vendor(id: offer.vendorId) else { continue }
            found.append(Suggestion(
                name: product.name, vendor: vendor.legalName, region: offer.shareUnit,
                category: product.category, offerId: offer.id
            ))
        }
        return found.isEmpty ? nil : found
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
        var id: String { offerId ?? name }
        let name: String
        let vendor: String
        /// Région du producteur, ou format de la part pour un lot (« sac de 10 kg »).
        let region: String
        let category: Product.Category
        /// Lot à ouvrir quand on touche le résultat ; nil pour une simple suggestion.
        var offerId: String? = nil

        static let catalog: [Suggestion] = [
            .init(name: "Riz basmati", vendor: "Ferme Lafleur", region: "Mirabel", category: .grains),
            .init(name: "Farine de blé", vendor: "Les Moulins du Nord", region: "Lanaudière", category: .flour),
            .init(name: "Lentilles corail", vendor: "Coop Agrinord", region: "Abitibi", category: .legumes),
            .init(name: "Pommes Cortland", vendor: "Verger Bilodeau", region: "Saint-Joseph-du-Lac", category: .produce),
            .init(name: "Huile de canola", vendor: "Coop Agrinord", region: "Montérégie", category: .oils),
            .init(name: "Œufs de poules en liberté", vendor: "Ferme Bio-Rive", region: "Saint-Jean-sur-Richelieu", category: .eggs)
        ]
    }

    /// Fiche du lot en feuille grande, avec son propre NavigationStack et un bouton Fermer.
    private struct OfferSheet: View {
        let offerId: String
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                OfferDetailScreen(offerId: offerId)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fermer", systemImage: "xmark") { dismiss() }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationBackground(Color.fond)
        }
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
                    Text("\(Image(systemName: "storefront.fill")) \(suggestion.vendor) · \(Image(systemName: suggestion.offerId == nil ? "mappin.and.ellipse" : "scalemass.fill")) \(suggestion.region)")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
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

extension OfferRoute: Identifiable {
    var id: String { offerId }
}
