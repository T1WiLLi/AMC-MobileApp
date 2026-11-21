// PickupViewModel.swift
// F5 Cueillette (T-019) : parts du ménage à récupérer, QR, créneau, point de cueillette et hôte.

import Foundation
import Observation

@Observable
@MainActor
final class PickupViewModel {
    /// Un article à récupérer (« Pommes de terre jaunes · 2 × sac de 10 kg »).
    nonisolated struct Item: Identifiable, Sendable, Hashable {
        var groupOrderId: String
        var product: Product
        var offer: Offer
        /// Parts du ménage.
        var quantity: Int
        /// Prix à payer à la cueillette (prix final si figé, sinon palier courant).
        var totalCents: Cents
        var isPickedUp: Bool

        var id: String { groupOrderId }
    }

    nonisolated struct Content: Sendable, Hashable {
        /// Point choisi par le groupe ; nil tant que le coordonnateur n'en a pas choisi (part réservée quand même).
        var pickupPoint: PickupPoint?
        /// Prochain créneau (à venir ou en cours), nil s'il n'y en a pas.
        var slot: PickupSlot?
        /// Prénom de l'hôte (« Montre ce code à Amina »), nil s'il est introuvable.
        var hostFirstName: String?
        var items: [Item]
        /// Contenu du QR à afficher.
        var qrPayload: String
        /// Code lisible de la commande (« GRN-4821 »).
        var orderCode: String

        var totalCents: Cents { items.reduce(0) { $0 + $1.totalCents } }

        /// Minutes avant le début du créneau (0 s'il est commencé), nil sans créneau. Pour « Cueillette dans 25 min ».
        func minutesUntilPickup(from now: Date = .now) -> Int? {
            slot.map { max(0, Int($0.start.timeIntervalSince(now) / 60)) }
        }
    }

    /// `.empty` quand le ménage n'a aucune part à récupérer.
    private(set) var state: LoadState<Content> = .idle

    private let repositories: AppRepositories
    private let householdId: String
    private let groupId: String

    init(repositories: AppRepositories, householdId: String, groupId: String) {
        self.repositories = repositories
        self.householdId = householdId
        self.groupId = groupId
    }

    func load() async {
        // Rechargement (retour sur l'onglet) : on garde le contenu ou l'état vide affiché, sans clignoter.
        switch state {
        case .loaded, .empty: break
        default: state = .loading
        }
        let repositories = repositories, householdId = householdId, groupId = groupId
        do {
            let content = try await Self.content(householdId: householdId, groupId: groupId, repositories: repositories)
            if let content { state = .loaded(content) } else { state = .empty }
        } catch {
            state = .failed(AppError(error))
        }
    }

    nonisolated private static func content(
        householdId: String, groupId: String, repositories: AppRepositories
    ) async throws -> Content? {
        let orders = try await repositories.groupOrders.groupOrders(ofGroup: groupId)
            .filter { $0.status != .cancelled && $0.status != .delivered }
        var items: [Item] = []
        var qrCodes: [String] = []
        var pickupPointId: String?
        var slots: [PickupSlot] = []
        for order in orders {
            let shares = try await repositories.groupOrders.shares(ofGroupOrder: order.id)
            guard let share = shares.first(where: { $0.householdId == householdId }), share.quantity > 0 else { continue }
            let offer = try await repositories.offers.offer(id: order.offerId)
            let product = try await repositories.vendors.product(id: offer.productId)
            let price = share.finalUnitPriceCents
                ?? OfferPricing(offer: offer, product: product, committedShares: order.committedShares).currentPriceCents
            items.append(Item(groupOrderId: order.id, product: product, offer: offer, quantity: share.quantity,
                              totalCents: price * share.quantity, isPickedUp: share.isPickedUp))
            if let code = share.qrCode { qrCodes.append(code) }
            pickupPointId = pickupPointId ?? order.pickupPointId
            slots += order.pickupSlots
        }
        // Une part réservée s'affiche même avant que le groupe ait choisi son point de cueillette.
        guard !items.isEmpty else { return nil }

        var point: PickupPoint?
        if let pickupPointId, !pickupPointId.isEmpty {
            point = try await repositories.pickupPoints.pickupPoint(id: pickupPointId)
        }
        let now = Date.now
        let slot = (slots + (point?.slots ?? [])).filter { $0.end > now }.min { $0.start < $1.start }
        // L'hôte est un détail : son absence ne doit pas bloquer la cueillette.
        var host: AppUser?
        if let point { host = try? await repositories.users.user(id: point.hostUserId) }
        let code = orderCode(householdId: householdId, groupId: groupId)
        return Content(
            pickupPoint: point,
            slot: slot,
            hostFirstName: host?.displayName.split(separator: " ").first.map(String.init),
            items: items,
            qrPayload: qrCodes.first ?? "grenier://cueillette/\(groupId)/\(householdId)",
            orderCode: code
        )
    }

    /// Code stable « GRN-1234 » dérivé des ids (pas `hashValue`, qui change à chaque lancement).
    nonisolated static func orderCode(householdId: String, groupId: String) -> String {
        let value = "\(groupId)/\(householdId)".unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 9_000 }
        return "GRN-\(1_000 + value)"
    }
}
