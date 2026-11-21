// CartViewModel.swift
// « Panier » d'une famille (T-062, RQ-046 à RQ-048) : toutes ses parts dans les commandes encore ouvertes,
// tous groupes confondus, avec prix du palier courant, économie et temps restant.
// Usage : `CartViewModel(repositories:householdId:)`, puis `await load()` dans `.task` ;
// `updateQuantity(_:to:)` et `cancel(_:)` rechargent le panier après l'écriture (pas d'optimisme).
// Temps réel (T-096, S-05) : `.task { await viewModel.load(); await viewModel.observe() }` — chaque ligne suit
// sa commande (palier, prix, total, économie recalculés quand d'autres familles réservent) ; s'arrête avec la
// tâche. Une écoute coupée garde le panier affiché et met `isLive` à false.

import Foundation
import Observation

@Observable
@MainActor
final class CartViewModel {
    /// Une part du ménage dans une commande ouverte.
    nonisolated struct Line: Identifiable, Sendable, Hashable {
        var offer: Offer
        var product: Product
        var group: NeighborhoodGroup
        var groupOrder: GroupOrder
        /// Parts réservées par le ménage.
        var quantity: Int
        /// Temps restant avant la date limite au moment du chargement, en secondes (0 si passée).
        var timeRemaining: TimeInterval
        /// Date limite non passée et commande ouverte ou palier atteint.
        var canEdit: Bool

        /// Une ligne par commande : le ménage n'y a qu'une part.
        var id: String { groupOrder.id }
        var productName: String { product.name }
        var groupName: String { group.name }
        var deadline: Date { offer.deadline }
        /// Prix, palier et économie actuels du groupe (mêmes règles que la fiche du lot).
        var pricing: OfferPricing {
            OfferPricing(offer: offer, product: product, committedShares: groupOrder.committedShares)
        }
        /// Prix d'une part au palier courant.
        var unitPriceCents: Cents { pricing.currentPriceCents }
        var lineTotalCents: Cents { pricing.totalCents(forShares: quantity) }
        /// Économie vs le prix d'épicerie de référence.
        var savingsCents: Cents { pricing.savingsCents(forShares: quantity) }
    }

    nonisolated struct Content: Sendable, Hashable {
        /// Lignes triées par date limite (la plus proche d'abord).
        var lines: [Line]

        /// Total estimé au prix des paliers courants (peut encore baisser).
        var estimatedTotalCents: Cents { lines.reduce(0) { $0 + $1.lineTotalCents } }
        var totalSavingsCents: Cents { lines.reduce(0) { $0 + $1.savingsCents } }
        var shareCount: Int { lines.reduce(0) { $0 + $1.quantity } }
    }

    /// `.empty` quand le ménage n'a aucune part en cours.
    private(set) var state: LoadState<Content> = .idle
    /// Écriture en cours (désactive les boutons).
    private(set) var isSaving = false
    /// Dernière erreur d'une action ; remise à nil par la vue.
    var actionError: AppError?
    /// L'écoute en direct tourne (`observe()`). Repasse à false quand elle s'arrête ou échoue.
    private(set) var isLive = false

    private let repositories: AppRepositories
    private let householdId: String
    private let now: @Sendable () -> Date

    init(repositories: AppRepositories, householdId: String, now: @escaping @Sendable () -> Date = { .now }) {
        self.repositories = repositories
        self.householdId = householdId
        self.now = now
    }

    var lines: [Line] { state.value?.lines ?? [] }

    // MARK: Chargement

    /// Charge (ou recharge) le panier. Garde le contenu affiché pendant un rechargement.
    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, householdId = householdId, now = now()
        do {
            let lines = try await Self.lines(of: householdId, now: now, repositories: repositories)
            state = lines.isEmpty ? .empty : .loaded(Content(lines: lines))
        } catch {
            state = .failed(AppError(error))
        }
    }

    /// Suit en temps réel la commande de chaque ligne. À lancer dans `.task` après `load()` ; s'arrête avec la tâche.
    func observe() async {
        guard let content = state.value else { return }
        // Abonnements ouverts avant de rendre la main : aucun changement n'est perdu une fois `isLive` vrai.
        var orderUpdates: [AsyncThrowingStream<GroupOrder, any Error>] = []
        for line in content.lines {
            orderUpdates.append(await repositories.groupOrders.observeGroupOrder(id: line.groupOrder.id))
        }
        isLive = true
        defer { isLive = false }
        await withTaskGroup(of: Void.self) { tasks in
            for updates in orderUpdates {
                tasks.addTask { [weak self] in
                    do {
                        for try await order in updates {
                            await self?.orderChanged(order)
                        }
                    } catch {}
                }
            }
        }
    }

    private func orderChanged(_ order: GroupOrder) {
        guard var content = state.value,
              let index = content.lines.firstIndex(where: { $0.groupOrder.id == order.id }) else { return }
        content.lines[index].groupOrder = order
        content.lines[index].canEdit = Self.canEdit(order, offer: content.lines[index].offer, now: now())
        state = .loaded(content)
    }

    // MARK: Actions

    /// Change le nombre de parts d'une ligne (0 retire la part). Refusé après la date limite.
    func updateQuantity(_ lineID: Line.ID, to quantity: Int) async {
        guard !isSaving, let line = lines.first(where: { $0.id == lineID }) else { return }
        guard quantity >= 0 else {
            actionError = .invalidInput(String(localized: "La quantité ne peut pas être négative."))
            return
        }
        guard Self.canEdit(line.groupOrder, offer: line.offer, now: now()) else {
            actionError = .orderClosed
            return
        }
        guard quantity != line.quantity else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repositories.groupOrders.setShare(
                quantity: quantity, householdId: householdId, groupOrderId: line.groupOrder.id
            )
        } catch {
            actionError = AppError(error)
        }
        await load()
    }

    /// Retire la part du ménage de cette commande.
    func cancel(_ lineID: Line.ID) async {
        await updateQuantity(lineID, to: 0)
    }

    // MARK: Assemblage

    /// Une commande est modifiable si elle est ouverte (ou palier atteint) et que sa date limite n'est pas passée.
    nonisolated static func canEdit(_ order: GroupOrder, offer: Offer, now: Date) -> Bool {
        TierEngine.isOpen(order) && now < offer.deadline
    }

    nonisolated static func lines(
        of householdId: String, now: Date, repositories: AppRepositories
    ) async throws -> [Line] {
        var lines: [Line] = []
        var products: [String: Product] = [:]
        for group in try await repositories.groups.groups(ofHousehold: householdId) {
            for order in try await repositories.groupOrders.groupOrders(ofGroup: group.id) where TierEngine.isOpen(order) {
                let quantity = try await OfferSummaryLoader.shareQuantity(
                    householdId: householdId, groupOrderId: order.id, repositories: repositories
                )
                guard quantity > 0 else { continue }
                let offer = try await repositories.offers.offer(id: order.offerId)
                let product: Product
                if let cached = products[offer.productId] {
                    product = cached
                } else {
                    product = try await repositories.vendors.product(id: offer.productId)
                    products[offer.productId] = product
                }
                lines.append(Line(
                    offer: offer, product: product, group: group, groupOrder: order, quantity: quantity,
                    timeRemaining: max(0, offer.deadline.timeIntervalSince(now)),
                    canEdit: canEdit(order, offer: offer, now: now)
                ))
            }
        }
        return lines.sorted { ($0.deadline, $0.id) < ($1.deadline, $1.id) }
    }
}
