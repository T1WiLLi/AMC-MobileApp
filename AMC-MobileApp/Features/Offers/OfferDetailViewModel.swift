// OfferDetailViewModel.swift
// F3 Fiche d'un lot et choix de part, F4 Palier franchi (T-019).
// La quantité est en parts (`Offer.shareUnit`, ex. « sac de 10 kg ») ; les prix sont par part.

import Foundation
import Observation

@Observable
@MainActor
final class OfferDetailViewModel {
    nonisolated struct Content: Sendable, Hashable {
        var offer: Offer
        var product: Product
        var vendor: Vendor
        /// Commande du groupe sur ce lot, nil si le groupe ne l'a pas lancée (réservation impossible).
        var groupOrder: GroupOrder?
        /// Parts déjà réservées par le ménage (0 si aucune).
        var myShareQuantity: Int

        var committedShares: Int { groupOrder?.committedShares ?? 0 }
        /// Prix, palier et économie actuels du groupe.
        var pricing: OfferPricing { OfferPricing(offer: offer, product: product, committedShares: committedShares) }
        /// Parts encore disponibles dans le lot (en plus de celles du ménage).
        var remainingShares: Int { max(0, offer.totalShares - committedShares) }
        /// Le groupe peut encore modifier les parts.
        var isOpen: Bool { groupOrder.map(OfferSummaryLoader.isActive) ?? false }
    }

    /// Ce que montre F4 quand la réservation fait franchir un palier.
    nonisolated struct TierCelebration: Sendable, Hashable {
        /// Numéro du palier débloqué (1 = premier) et nombre de paliers.
        var tierNumber: Int
        var tierCount: Int
        /// Prix d'une part avant et après (« 11,50 $ → 9,90 $ »).
        var previousPriceCents: Cents
        var newPriceCents: Cents
        /// Parts engagées par le groupe après la réservation.
        var committedShares: Int
        /// Part du ménage, son total au nouveau prix et son économie vs l'épicerie.
        var myQuantity: Int
        var myTotalCents: Cents
        var mySavingsCents: Cents

        var isLastTier: Bool { tierNumber == tierCount }
    }

    private(set) var state: LoadState<Content> = .idle
    /// Quantité choisie (en parts), liée au `Picker` « Ta part ».
    var selectedQuantity: Int = 1
    /// Réservation ou annulation en cours (désactive le bouton principal).
    private(set) var isSaving = false
    /// Dernière erreur d'une action ; remise à nil par la vue.
    var actionError: AppError?
    /// Non nil quand la dernière réservation a franchi un palier : la vue présente F4, puis appelle `dismissCelebration()`.
    private(set) var celebration: TierCelebration?

    private let repositories: AppRepositories
    private let offerId: String
    private let householdId: String
    private let groupId: String?

    /// `groupId` : groupe du ménage, pour trouver sa commande sur ce lot (`nil` = consultation seule).
    init(repositories: AppRepositories, offerId: String, householdId: String, groupId: String?) {
        self.repositories = repositories
        self.offerId = offerId
        self.householdId = householdId
        self.groupId = groupId
    }

    // MARK: Valeurs dérivées pour la vue

    /// Prix actuel du groupe (sans la sélection).
    var pricing: OfferPricing? { state.value?.pricing }

    /// Prix si la quantité choisie remplaçait la part actuelle du ménage (montre le palier qui tomberait).
    var projectedPricing: OfferPricing? {
        guard let content = state.value else { return nil }
        return content.pricing.with(committedShares: projectedCommittedShares(content))
    }

    /// Choix proposés dans le `Picker` (1, 2, 3 parts), limités à ce qui reste dans le lot.
    var quantityOptions: [Int] {
        guard let content = state.value else { return [] }
        let maximum = content.remainingShares + content.myShareQuantity
        return [1, 2, 3].filter { $0 <= maximum }
    }

    /// Total de la quantité choisie au prix projeté (« 26,00 $ »).
    var selectedTotalCents: Cents { projectedPricing?.totalCents(forShares: selectedQuantity) ?? 0 }

    /// Économie de la quantité choisie vs l'épicerie (« Tu économises 15 $ sur ta part »).
    var selectedSavingsCents: Cents { projectedPricing?.savingsCents(forShares: selectedQuantity) ?? 0 }

    /// La quantité choisie fait franchir un palier (pour annoncer « Ta part débloque le palier »).
    var selectionUnlocksTier: Bool {
        guard let pricing, let projectedPricing else { return false }
        return projectedPricing.tierNumber > pricing.tierNumber
    }

    /// Le bouton « Réserver » est actif.
    var canReserve: Bool {
        guard let content = state.value, content.isOpen, !isSaving else { return false }
        return selectedQuantity > 0 && selectedQuantity != content.myShareQuantity
            && quantityOptions.contains(selectedQuantity)
    }

    // MARK: Actions

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, offerId = offerId, householdId = householdId, groupId = groupId
        state = await .run {
            let offer = try await repositories.offers.offer(id: offerId)
            let product = try await repositories.vendors.product(id: offer.productId)
            let vendor = try await repositories.vendors.vendor(id: offer.vendorId)
            var order: GroupOrder?
            var myQuantity = 0
            if let groupId {
                order = try await repositories.groupOrders.groupOrders(ofGroup: groupId)
                    .first { $0.offerId == offerId }
                if let order {
                    myQuantity = try await OfferSummaryLoader.shareQuantity(
                        householdId: householdId, groupOrderId: order.id, repositories: repositories
                    )
                }
            }
            return Content(offer: offer, product: product, vendor: vendor, groupOrder: order, myShareQuantity: myQuantity)
        }
        if let content = state.value, content.myShareQuantity > 0 {
            selectedQuantity = content.myShareQuantity
        }
    }

    /// Réserve `selectedQuantity` parts (ou change la part). Si un palier tombe, remplit `celebration`.
    func reserve() async {
        await setShare(quantity: selectedQuantity)
    }

    /// Retire la part du ménage.
    func cancelShare() async {
        await setShare(quantity: 0)
    }

    func dismissCelebration() {
        celebration = nil
    }

    /// Suit la commande en temps réel (autres familles qui réservent). À lancer dans `.task` ; s'arrête avec la tâche.
    func observe() async {
        guard let orderId = state.value?.groupOrder?.id else { return }
        do {
            for try await order in await repositories.groupOrders.observeGroupOrder(id: orderId) {
                guard var content = state.value else { continue }
                content.groupOrder = order
                state = .loaded(content)
            }
        } catch {
            if !(error is CancellationError) { actionError = AppError(error) }
        }
    }

    private func setShare(quantity: Int) async {
        guard let content = state.value, !isSaving else { return }
        guard let order = content.groupOrder else {
            actionError = .invalidInput("Ton groupe n'a pas encore lancé de commande pour ce lot.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        let before = content.pricing
        do {
            let updated = try await repositories.groupOrders.setShare(
                quantity: quantity, householdId: householdId, groupOrderId: order.id
            )
            var newContent = content
            newContent.groupOrder = updated
            newContent.myShareQuantity = quantity
            state = .loaded(newContent)

            let after = newContent.pricing
            if quantity > 0, after.tierNumber > before.tierNumber {
                celebration = TierCelebration(
                    tierNumber: after.tierNumber,
                    tierCount: after.tierCount,
                    previousPriceCents: before.currentPriceCents,
                    newPriceCents: after.currentPriceCents,
                    committedShares: updated.committedShares,
                    myQuantity: quantity,
                    myTotalCents: after.totalCents(forShares: quantity),
                    mySavingsCents: after.savingsCents(forShares: quantity)
                )
            }
        } catch {
            actionError = AppError(error)
        }
    }

    private func projectedCommittedShares(_ content: Content) -> Int {
        content.committedShares - content.myShareQuantity + selectedQuantity
    }
}
