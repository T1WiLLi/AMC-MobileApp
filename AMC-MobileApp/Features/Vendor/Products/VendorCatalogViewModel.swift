// VendorCatalogViewModel.swift
// Catalogue du vendeur (T-089, S-04) : ses produits, triés par nom, mis à jour sur place dès qu'un produit
// est créé, modifié ou retiré (pas besoin d'attendre un rechargement).
//
// Usage :
//   @State private var model = VendorCatalogViewModel(repositories: repos, vendorId: id)
//   .task { await model.load() }  ·  .refreshable { await model.refresh() }
//   Après l'éditeur : `model.productSaved(product)` / `model.productDeleted(id:)`.

import Foundation
import Observation

@Observable @MainActor
final class VendorCatalogViewModel {
    private(set) var state: LoadState<[Product]> = .idle
    /// Produit tout juste créé ou modifié, mis en évidence dans la liste.
    private(set) var highlightedProductId: String?

    let vendorId: String
    private let repositories: AppRepositories

    init(repositories: AppRepositories, vendorId: String) {
        self.repositories = repositories
        self.vendorId = vendorId
    }

    var products: [Product] { state.value ?? [] }

    func load() async {
        state = .loading
        await refresh()
    }

    func refresh() async {
        do {
            state = .from(try await repositories.vendors.products(ofVendor: vendorId))
        } catch {
            state = .failed(AppError(error))
        }
    }

    /// Ajoute ou remplace le produit dans la liste, sans recharger.
    func productSaved(_ product: Product) {
        guard product.vendorId == vendorId else { return }
        var list = products.filter { $0.id != product.id }
        list.append(product)
        state = .from(Self.sorted(list))
        highlightedProductId = product.id
    }

    func productDeleted(id: String) {
        state = .from(products.filter { $0.id != id })
        if highlightedProductId == id { highlightedProductId = nil }
    }

    /// Ordre alphabétique français (« Œufs » avec les O, accents ignorés).
    nonisolated static func sorted(_ products: [Product]) -> [Product] {
        products.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
