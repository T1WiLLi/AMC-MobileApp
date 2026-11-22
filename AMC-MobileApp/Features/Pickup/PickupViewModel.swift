// PickupViewModel.swift
// F5 Cueillette (T-019) : parts du ménage à récupérer, QR, créneau, point de cueillette et hôte.
// Retour samuel : les articles sont rangés par lieu (`Place`), comme le bordereau du vendeur (`DeliveryManifest`) :
// une section par point de cueillette, et « Lieu à confirmer » pour les commandes sans point.

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

        var id: String { groupOrderId }
    }

    /// Un lieu de cueillette et ce qu'on y récupère.
    nonisolated struct Place: Identifiable, Sendable, Hashable {
        /// nil : commandes sans point de cueillette (« Lieu à confirmer »).
        var pickupPoint: PickupPoint?
        /// Prochain créneau à ce lieu (à venir ou en cours), nil s'il n'y en a pas.
        var slot: PickupSlot?
        /// Prénom de l'hôte du lieu, nil s'il est introuvable ou si c'est le membre connecté.
        var hostFirstName: String?
        var items: [Item]

        var id: String { pickupPoint?.id ?? DeliveryManifest.unassignedStopId }
        var totalCents: Cents { items.reduce(0) { $0 + $1.totalCents } }
        var pickedUpCount: Int { items.filter(\.isPickedUp).count }
    }

    /// Un article et le lieu où le cueillir, avant le regroupement.
    nonisolated struct Entry: Sendable, Hashable {
        var item: Item
        /// Point de la commande (ou zone de livraison du groupe), nil s'il n'y en a pas.
        var pickupPointId: String?
        var slots: [PickupSlot]
    }

    nonisolated struct Content: Sendable, Hashable {
        /// Lieux dans l'ordre des commandes (groupe actif d'abord), « Lieu à confirmer » en dernier.
        var places: [Place]
        /// Contenu du QR à afficher.
        var qrPayload: String
        /// Code lisible de la commande (« GRN-4821 »).
        var orderCode: String

        var items: [Item] { places.flatMap(\.items) }
        var totalCents: Cents { items.reduce(0) { $0 + $1.totalCents } }
        /// Premier lieu avec un point ; nil tant qu'aucune commande n'a de point (part réservée quand même).
        var pickupPoint: PickupPoint? { places.lazy.compactMap(\.pickupPoint).first }
        /// Prénom de l'hôte (« Montre ce code à Amina ») quand il n'y a qu'un lieu, nil sinon.
        var hostFirstName: String? { places.count == 1 ? places.first?.hostFirstName : nil }
        /// Prochain créneau, tous lieux confondus.
        var slot: PickupSlot? { places.compactMap(\.slot).min { $0.start < $1.start } }
        /// Nombre de lieux avec un point de cueillette.
        var pointCount: Int { places.filter { $0.pickupPoint != nil }.count }

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

    nonisolated private static func content(
        householdId: String, groupId: String, userId: String, repositories: AppRepositories
    ) async throws -> Content? {
        // Noms des membres (« Récupéré par Amina ») : un détail, jamais bloquant.
        let household = try? await repositories.users.household(id: householdId)
        // Toutes les parts du ménage, dans tous ses groupes : une part réservée dans un autre groupe que le groupe
        // actif apparaît aussi. Le groupe actif d'abord (son point de cueillette passe en premier).
        let orders = try await activeOrders(householdId: householdId, activeGroupId: groupId, repositories: repositories)
        var entries: [Entry] = []
        var qrCodes: [String] = []
        // Commandes sans point choisi : la zone de livraison de leur groupe (liste lue seulement s'il le faut).
        let allPoints = orders.contains { ($0.pickupPointId ?? "").isEmpty }
            ? ((try? await repositories.pickupPoints.pickupPoints()) ?? []) : []
        for order in orders {
            let shares = try await repositories.groupOrders.shares(ofGroupOrder: order.id)
            guard let share = shares.first(where: { $0.householdId == householdId }), share.quantity > 0 else { continue }
            let offer = try await repositories.offers.offer(id: order.offerId)
            let product = try await repositories.vendors.product(id: offer.productId)
            let price = share.finalUnitPriceCents
                ?? OfferPricing(offer: offer, product: product, committedShares: order.committedShares).currentPriceCents
            let item = Item(groupOrderId: order.id, product: product, offer: offer, quantity: share.quantity,
                            totalCents: price * share.quantity, isPickedUp: share.isPickedUp,
                            pickedUpByName: share.pickedUpBy.flatMap { HouseholdMembership.firstName(of: $0, in: household) })
            entries.append(Entry(item: item, pickupPointId: PickupPoint.resolvedId(for: order, in: allPoints),
                                 slots: order.pickupSlots))
            if let code = share.qrCode { qrCodes.append(code) }
        }
        // Une part réservée s'affiche même avant que le groupe ait choisi son point de cueillette.
        guard !entries.isEmpty else { return nil }

        var points: [String: PickupPoint] = [:]
        for id in Set(entries.compactMap(\.pickupPointId)) {
            if let known = allPoints.first(where: { $0.id == id }) {
                points[id] = known
                continue
            }
            do {
                points[id] = try await repositories.pickupPoints.pickupPoint(id: id)
            } catch AppError.notFound {
                // Point supprimé : ses articles passent dans « Lieu à confirmer ».
            }
        }
        // L'hôte est un détail : son absence ne doit pas bloquer la cueillette.
        // Quand le membre est lui-même l'hôte du point, « Montre ce code à Amina » n'a pas de sens : on dit « l'hôte ».
        var hostFirstNames: [String: String] = [:]
        for point in points.values {
            guard let host = try? await repositories.users.user(id: point.hostUserId), host.id != userId,
                  let first = host.displayName.split(separator: " ").first else { continue }
            hostFirstNames[point.id] = String(first)
        }
        let code = orderCode(householdId: householdId, groupId: groupId)
        return Content(
            places: places(from: entries, points: points, hostFirstNames: hostFirstNames),
            // Le QR est celui de la part du ménage (le même pour tous ses membres), suivi du membre qui le montre.
            qrPayload: qrCodes.first.map { PickupDesk.memberCode($0, memberId: userId) }
                ?? "grenier://cueillette/\(groupId)/\(householdId)",
            orderCode: code
        )
    }

    /// Range les articles par lieu, comme `DeliveryManifest` : un lieu par point connu, dans l'ordre où il apparaît
    /// (groupe actif d'abord) ; les articles sans point, ou dont le point est inconnu, dans « Lieu à confirmer »
    /// en dernier. Le créneau d'un lieu est le prochain de ses commandes et du point.
    nonisolated static func places(
        from entries: [Entry], points: [String: PickupPoint], hostFirstNames: [String: String] = [:],
        now: Date = .now
    ) -> [Place] {
        var order: [String] = []
        var grouped: [String: (items: [Item], slots: [PickupSlot])] = [:]
        for entry in entries {
            let key = entry.pickupPointId.flatMap { points[$0] == nil ? nil : $0 } ?? DeliveryManifest.unassignedStopId
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: ([], [])].items.append(entry.item)
            grouped[key, default: ([], [])].slots += entry.slots
        }
        let keys = order.filter { $0 != DeliveryManifest.unassignedStopId }
            + order.filter { $0 == DeliveryManifest.unassignedStopId }
        return keys.compactMap { key in
            guard let group = grouped[key] else { return nil }
            let point = points[key]
            let slot = (group.slots + (point?.slots ?? [])).filter { $0.end > now }.min { $0.start < $1.start }
            return Place(pickupPoint: point, slot: slot, hostFirstName: hostFirstNames[key], items: group.items)
        }
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
