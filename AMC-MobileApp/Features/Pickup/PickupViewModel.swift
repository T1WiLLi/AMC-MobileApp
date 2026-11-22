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
        /// T-159 : prénom du membre du ménage qui a récupéré la part (« Récupéré par Amina »).
        var pickedUpByName: String? = nil
        /// T-173 : qui, dans le ménage, s'est engagé à récupérer cette part.
        var claim: PickupClaim.State = .open
        /// T-173 : prénom du membre engagé (« Amina »), nil s'il est inconnu ou si c'est la personne connectée.
        var claimerName: String? = nil

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
        /// T-173 : le ménage compte plusieurs comptes : on montre qui s'occupe de la cueillette.
        var isSharedHousehold: Bool = false

        var totalCents: Cents { items.reduce(0) { $0 + $1.totalCents } }

        /// Minutes avant le début du créneau (0 s'il est commencé), nil sans créneau. Pour « Cueillette dans 25 min ».
        func minutesUntilPickup(from now: Date = .now) -> Int? {
            slot.map { max(0, Int($0.start.timeIntervalSince(now) / 60)) }
        }
    }

    /// `.empty` quand le ménage n'a aucune part à récupérer.
    private(set) var state: LoadState<Content> = .idle
    /// T-173 : commande dont l'engagement est en cours d'écriture (bouton désactivé).
    private(set) var claimingOrderId: String?
    /// T-173 : retour du dernier « Je m'en occupe » perdu ou échoué (« Ta famille récupère déjà… »).
    private(set) var claimMessage: String?

    private let repositories: AppRepositories
    private let householdId: String
    private let groupId: String
    /// T-159 : membre connecté ; son uid suit le QR du ménage pour noter qui récupère la part.
    private let userId: String

    init(repositories: AppRepositories, householdId: String, groupId: String, userId: String = "") {
        self.repositories = repositories
        self.householdId = householdId
        self.groupId = groupId
        self.userId = userId
    }

    func load() async {
        // Rechargement (retour sur l'onglet) : on garde le contenu ou l'état vide affiché, sans clignoter.
        switch state {
        case .loaded, .empty: break
        default: state = .loading
        }
        let repositories = repositories, householdId = householdId, groupId = groupId, userId = userId
        do {
            let content = try await Self.content(householdId: householdId, groupId: groupId, userId: userId,
                                                 repositories: repositories)
            if let content { state = .loaded(content) } else { state = .empty }
        } catch {
            state = .failed(AppError(error))
        }
    }

    // MARK: - T-173 : un seul membre récupère la part

    /// « Je m'en occupe » : le premier membre l'emporte. Perdu : message « Ta famille récupère déjà… » et liste relue.
    func claim(_ item: Item) async {
        guard claimingOrderId == nil, !userId.isEmpty else { return }
        claimingOrderId = item.groupOrderId
        claimMessage = nil
        defer { claimingOrderId = nil }
        do {
            let outcome = try await repositories.groupOrders.claimPickup(
                householdId: householdId, groupOrderId: item.groupOrderId, userId: userId, at: .now
            )
            switch outcome {
            case .claimed(let share):
                update(item.groupOrderId) { $0.claim = PickupClaim.state(of: share, for: self.userId); $0.claimerName = nil }
            case .takenBy(let other):
                let household = try? await repositories.users.household(id: householdId)
                let name = HouseholdMembership.firstName(of: other, in: household)
                claimMessage = PickupClaim.takenMessage(claimerName: name)
                update(item.groupOrderId) { $0.claim = .takenBy(other); $0.claimerName = name }
            case .alreadyPickedUp:
                await load()
            }
        } catch {
            claimMessage = AppError(error).message
        }
    }

    /// « Je ne peux plus » : la part redevient libre pour les autres membres.
    func release(_ item: Item) async {
        guard claimingOrderId == nil, !userId.isEmpty else { return }
        claimingOrderId = item.groupOrderId
        claimMessage = nil
        defer { claimingOrderId = nil }
        do {
            try await repositories.groupOrders.releasePickup(householdId: householdId, groupOrderId: item.groupOrderId,
                                                             userId: userId)
            update(item.groupOrderId) { $0.claim = .open; $0.claimerName = nil }
        } catch {
            claimMessage = AppError(error).message
            await load()
        }
    }

    private func update(_ groupOrderId: String, _ change: (inout Item) -> Void) {
        guard case .loaded(var content) = state,
              let index = content.items.firstIndex(where: { $0.groupOrderId == groupOrderId }) else { return }
        change(&content.items[index])
        state = .loaded(content)
    }

    nonisolated private static func content(
        householdId: String, groupId: String, userId: String, repositories: AppRepositories
    ) async throws -> Content? {
        // Noms des membres (« Récupéré par Amina ») : un détail, jamais bloquant.
        let household = try? await repositories.users.household(id: householdId)
        // Toutes les parts du ménage, dans tous ses groupes : une part réservée dans un autre groupe que le groupe
        // actif apparaît aussi. Le groupe actif d'abord (son point de cueillette passe en premier).
        let orders = try await activeOrders(householdId: householdId, activeGroupId: groupId, repositories: repositories)
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
            let claim = PickupClaim.state(of: share, for: userId)
            var claimerName: String?
            if case .takenBy(let other) = claim { claimerName = HouseholdMembership.firstName(of: other, in: household) }
            items.append(Item(groupOrderId: order.id, product: product, offer: offer, quantity: share.quantity,
                              totalCents: price * share.quantity, isPickedUp: share.isPickedUp,
                              pickedUpByName: share.pickedUpBy.flatMap { HouseholdMembership.firstName(of: $0, in: household) },
                              claim: claim, claimerName: claimerName))
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
            // Le QR est celui de la part du ménage (le même pour tous ses membres), suivi du membre qui le montre.
            qrPayload: qrCodes.first.map { PickupDesk.memberCode($0, memberId: userId) }
                ?? "grenier://cueillette/\(groupId)/\(householdId)",
            orderCode: code,
            isSharedHousehold: (household?.userIds.count ?? 1) > 1 && !userId.isEmpty
        )
    }

    /// Commandes non annulées ni livrées des groupes du ménage, celles du groupe actif d'abord.
    /// La liste des groupes est un détail : si elle échoue, on garde au moins le groupe actif.
    nonisolated static func activeOrders(
        householdId: String, activeGroupId: String, repositories: AppRepositories
    ) async throws -> [GroupOrder] {
        let memberGroupIds = (try? await repositories.groups.groups(ofHousehold: householdId).map(\.id)) ?? []
        let groupIds = [activeGroupId] + memberGroupIds.filter { $0 != activeGroupId }
        var orders: [GroupOrder] = []
        var seen = Set<String>()
        for groupId in groupIds {
            for order in try await repositories.groupOrders.groupOrders(ofGroup: groupId)
            where order.status != .cancelled && order.status != .delivered && seen.insert(order.id).inserted {
                orders.append(order)
            }
        }
        return orders
    }

    /// Code stable « GRN-1234 » dérivé des ids (pas `hashValue`, qui change à chaque lancement).
    nonisolated static func orderCode(householdId: String, groupId: String) -> String {
        let value = "\(groupId)/\(householdId)".unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 9_000 }
        return "GRN-\(1_000 + value)"
    }
}
