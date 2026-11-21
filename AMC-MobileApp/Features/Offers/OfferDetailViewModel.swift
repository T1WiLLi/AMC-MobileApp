// OfferDetailViewModel.swift
// F3 Fiche d'un lot et choix de part, F4 Palier franchi (T-019).
// La quantité est en parts (`Offer.shareUnit`, ex. « sac de 10 kg ») ; les prix sont par part.
//
// Temps réel (T-096, S-05) : dans l'écran,
//     .task { await viewModel.load(); await viewModel.observe() }
// `observe()` suit la commande du groupe (parts, ménages, palier, prix, économie) et s'arrête avec la tâche.
// Quand une AUTRE famille fait franchir un palier pendant l'écoute, `tierUnlockCount` augmente de 1 et
// `liveUnlock` contient la célébration à montrer (puis `dismissLiveUnlock()`), par exemple :
//     .onChange(of: viewModel.tierUnlockCount) { … }   ou une feuille liée à `viewModel.liveUnlock != nil`
// Sa propre réservation continue de remplir `celebration` (pas `liveUnlock`). Une écoute coupée garde les
// données affichées et met `isLive` à false (pas d'écran d'erreur).

import Foundation
import Observation

@Observable
@MainActor
final class OfferDetailViewModel {
    nonisolated struct Content: Sendable, Hashable {
        var offer: Offer
        var product: Product
        var vendor: Vendor
        /// Commande du groupe sur ce lot, nil si personne du groupe n'a encore réservé.
        var groupOrder: GroupOrder?
        /// Parts déjà réservées par le ménage (0 si aucune).
        var myShareQuantity: Int
        /// Sans commande du groupe : la première réservation l'ouvrira (lot actif, date limite future, ménage dans un groupe).
        var canStartOrder: Bool = false

        var committedShares: Int { groupOrder?.committedShares ?? 0 }
        /// Prix, palier et économie actuels du groupe.
        var pricing: OfferPricing { OfferPricing(offer: offer, product: product, committedShares: committedShares) }
        /// Parts encore disponibles dans le lot (en plus de celles du ménage).
        var remainingShares: Int { max(0, offer.totalShares - committedShares) }
        /// Le groupe peut encore modifier les parts.
        var isOpen: Bool { groupOrder.map(OfferSummaryLoader.isActive) ?? canStartOrder }
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
    /// L'écoute en direct de la commande tourne (`observe()`). Repasse à false quand elle s'arrête ou échoue.
    private(set) var isLive = false
    /// +1 chaque fois qu'une autre famille fait monter le palier pendant l'écoute (jamais à la première émission).
    private(set) var tierUnlockCount = 0
    /// Numéro (1 = premier) du dernier palier franchi en direct par une autre famille.
    private(set) var lastUnlockedTierNumber: Int?
    /// Célébration à montrer pour le palier franchi en direct ; remise à nil par `dismissLiveUnlock()`.
    private(set) var liveUnlock: TierCelebration?

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
            let canStartOrder = order == nil && groupId != nil && offer.status == .active && offer.deadline > .now
            return Content(
                offer: offer, product: product, vendor: vendor, groupOrder: order, myShareQuantity: myQuantity,
                canStartOrder: canStartOrder
            )
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

    func dismissLiveUnlock() {
        liveUnlock = nil
    }

    /// Suit la commande en temps réel (autres familles qui réservent). À lancer dans `.task` après `load()` ;
    /// s'arrête avec la tâche. Sans commande du groupe sur ce lot, rend la main tout de suite.
    func observe() async {
        guard let orderId = state.value?.groupOrder?.id else { return }
        await follow(await repositories.groupOrders.observeGroupOrder(id: orderId))
    }

    /// Applique chaque émission de `updates` (exposé pour les tests). La première émission sert de référence :
    /// elle met l'écran à jour sans célébrer.
    func follow(_ updates: AsyncThrowingStream<GroupOrder, any Error>) async {
        isLive = true
        defer { isLive = false }
        var isFirst = true
        do {
            for try await order in updates {
                apply(order, celebrate: !isFirst)
                isFirst = false
            }
        } catch {
            // Écoute coupée : on garde les dernières données ; `isLive` repasse à false.
        }
    }

    private func apply(_ order: GroupOrder, celebrate: Bool) {
        guard var content = state.value, content.groupOrder?.id == order.id else { return }
        let before = content.pricing
        content.groupOrder = order
        state = .loaded(content)
        let after = content.pricing
        // Pendant sa propre réservation, c'est `setShare` qui célèbre (`celebration`).
        guard celebrate, !isSaving, after.tierNumber > before.tierNumber else { return }
        tierUnlockCount += 1
        lastUnlockedTierNumber = after.tierNumber
        liveUnlock = TierCelebration(
            tierNumber: after.tierNumber,
            tierCount: after.tierCount,
            previousPriceCents: before.currentPriceCents,
            newPriceCents: after.currentPriceCents,
            committedShares: order.committedShares,
            myQuantity: content.myShareQuantity,
            myTotalCents: after.totalCents(forShares: content.myShareQuantity),
            mySavingsCents: after.savingsCents(forShares: content.myShareQuantity)
        )
    }

    private func setShare(quantity: Int) async {
        guard let content = state.value, !isSaving else { return }
        guard content.groupOrder != nil || (content.canStartOrder && quantity > 0), let groupId else {
            actionError = .invalidInput(String(localized: "Rejoins un groupe de quartier pour réserver ce lot."))
            return
        }
        isSaving = true
        defer { isSaving = false }
        let before = content.pricing
        do {
            // Première réservation du groupe sur ce lot : on ouvre la commande (T-033).
            let order: GroupOrder
            if let existing = content.groupOrder {
                order = existing
            } else {
                order = try await repositories.groupOrders.openGroupOrder(groupId: groupId, offerId: offerId)
            }
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
