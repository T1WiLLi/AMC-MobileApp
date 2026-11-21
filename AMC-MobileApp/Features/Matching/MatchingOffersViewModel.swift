// MatchingOffersViewModel.swift
// S-09 côté famille (T-110) : « Offres qui correspondent à vos souhaits ».
// Lots actifs qui desservent le groupe (même règle que le fil : `OfferSummaryLoader.offer(_:serves:)`)
// et dont le produit est d'une catégorie que ma famille a demandée.
//
// Usage : `.task { await model.load() }` ; chaque `Item` ouvre `OfferRoute(offerId:)`.

import Foundation
import Observation

@Observable @MainActor
final class MatchingOffersViewModel {
    nonisolated struct Item: Identifiable, Sendable, Hashable {
        var offer: Offer
        var product: Product
        var vendor: Vendor

        var id: String { offer.id }
    }

    /// Lots correspondants, par date limite ; `.empty` si aucun (ou aucune envie).
    private(set) var state: LoadState<[Item]> = .idle
    /// Vrai si ma famille n'a encore aucune envie dans ce groupe (l'écran invite à en dire une).
    private(set) var hasNoWish = false

    let groupId: String
    let householdId: String
    private let repositories: AppRepositories

    init(repositories: AppRepositories, groupId: String, householdId: String) {
        self.repositories = repositories
        self.groupId = groupId
        self.householdId = householdId
    }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            let wishes = try await repositories.wishes.wishes(ofHousehold: householdId, inGroup: groupId)
            hasNoWish = wishes.isEmpty
            let categories = Set(wishes.map(\.category))
            guard !categories.isEmpty else {
                state = .empty
                return
            }
            let group = try await repositories.groups.group(id: groupId)
            let now = Date.now
            let offers = try await repositories.offers.activeOffers(inZone: nil)
                .filter { OfferSummaryLoader.offer($0, serves: group) && $0.deadline > now }
            var items: [Item] = []
            for offer in offers {
                guard let product = try? await repositories.vendors.product(id: offer.productId),
                      categories.contains(product.category),
                      let vendor = try? await repositories.vendors.vendor(id: offer.vendorId) else { continue }
                items.append(Item(offer: offer, product: product, vendor: vendor))
            }
            state = .from(items.sorted { $0.offer.deadline < $1.offer.deadline })
        } catch {
            state = .failed(AppError(error))
        }
    }
}
