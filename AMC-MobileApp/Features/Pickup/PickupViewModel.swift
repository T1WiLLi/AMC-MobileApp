// PickupViewModel.swift
// F5 Cueillette (T-019) : parts du ménage à récupérer, QR, créneau, point de cueillette et hôte.
// Retour samuel : les articles sont rangés par lieu (`Place`), comme le bordereau du vendeur (`DeliveryManifest`) :
// une section par point de cueillette, et « Lieu à confirmer » pour les commandes sans point.
// T-198 (retour samuel) : au-dessus des lieux, une section par GROUPE du ménage, avec un seul QR par groupe
// (`GroupPickup.qrPayload`, les codes à jeton de ses commandes mis bout à bout : `PickupDesk.bundleCode`).

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
        /// Statut de la commande : fermée = en route, livrée = arrivée chez l'hôte (seulement là, on vient la chercher).
        var orderStatus: GroupOrder.Status = .open
        /// Contenu du QR de CETTE commande (`PickupViewModel.qrPayload(for:code:memberId:)`), nil tant que la
        /// commande n'est pas fermée : l'hôte scanne un code par commande.
        var pickupCode: String? = nil

        var id: String { groupOrderId }

        /// Arrivée au point et pas encore récupérée : la famille peut venir la chercher.
        var isReadyToPickUp: Bool { orderStatus == .delivered && !isPickedUp }
        /// Commande fermée : la livraison est en route vers le point.
        var isOnTheWay: Bool { orderStatus == .closed && !isPickedUp }
    }

    /// Bandeau d'état de la livraison en haut de la Cueillette.
    nonisolated enum Arrival: Sendable, Hashable {
        /// Au moins un article est arrivé chez l'hôte : « Arrivée ! Viens la chercher ».
        case arrived(Place)
        /// Rien n'est encore arrivé, mais au moins une commande est fermée : « En route ».
        case onTheWay
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

        /// Commandes à cueillir à ce lieu qui ont un code, ou pourquoi il n'y en a pas.
        var codeState: CodeState { CodeState(items: items) }
    }

    /// Un groupe du ménage, ses lieux, et UN QR pour toutes ses commandes.
    nonisolated struct GroupPickup: Identifiable, Sendable, Hashable {
        var groupId: String
        /// Nom du groupe (« Voisins de Saint-Michel »), nil s'il est illisible.
        var groupName: String?
        /// Lieux du groupe (souvent un seul : son point de cueillette), « Lieu à confirmer » en dernier.
        var places: [Place]

        var id: String { groupId }
        var items: [Item] { places.flatMap(\.items) }
        var totalCents: Cents { items.reduce(0) { $0 + $1.totalCents } }
        /// Prénom de l'hôte quand le groupe n'a qu'un lieu.
        var hostFirstName: String? { places.count == 1 ? places.first?.hostFirstName : nil }
        var title: String { groupName ?? String(localized: "Mon groupe") }

        /// Ce que la carte du code affiche pour le groupe.
        var codeState: CodeState { CodeState(items: items) }

        /// Contenu du QR du groupe : les codes de ses commandes fermées pas encore récupérées, en un seul code
        /// (`PickupDesk.bundleCode`). nil sans commande fermée : pas de faux QR.
        var qrPayload: String? {
            guard case .codes(let items, _) = codeState else { return nil }
            return PickupDesk.bundleCode(items.compactMap(\.pickupCode))
        }
    }

    /// Ce que la carte du code affiche pour un lieu.
    nonisolated enum CodeState: Sendable, Hashable {
        /// Un QR par commande fermée ; `waitingCount` commandes encore ouvertes n'ont pas encore de code.
        case codes([Item], waitingCount: Int)
        /// Aucune commande fermée à ce lieu : pas de code (aucun faux QR).
        case awaitingClosure
        /// Tout est récupéré.
        case allPickedUp

        /// Commandes pas encore récupérées : celles qui ont un code, et combien attendent encore leur clôture.
        init(items: [Item]) {
            let pending = items.filter { !$0.isPickedUp }
            let codes = pending.filter { $0.pickupCode != nil }
            if pending.isEmpty { self = .allPickedUp }
            else if codes.isEmpty { self = .awaitingClosure }
            else { self = .codes(codes, waitingCount: pending.count - codes.count) }
        }
    }

    /// Un article et le lieu où le cueillir, avant le regroupement.
    nonisolated struct Entry: Sendable, Hashable {
        var item: Item
        /// Point de la commande (ou zone de livraison du groupe), nil s'il n'y en a pas.
        var pickupPointId: String?
        var slots: [PickupSlot]
        /// Groupe de la commande (T-198).
        var groupId: String = ""
    }

    nonisolated struct Content: Sendable, Hashable {
        /// Groupes du ménage qui ont une part à cueillir, le groupe actif d'abord.
        var groups: [GroupPickup]

        init(groups: [GroupPickup]) { self.groups = groups }

        /// Un seul groupe (aperçus, tests du rangement par lieu).
        init(places: [Place]) {
            groups = [GroupPickup(groupId: "", groupName: nil, places: places)]
        }

        /// Lieux de tous les groupes, dans l'ordre des groupes.
        var places: [Place] { groups.flatMap(\.places) }

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

        /// Le même contenu limité à un groupe (sélecteur de groupe en haut de la Cueillette) ; le premier par défaut.
        func scoped(to groupId: String?) -> Content {
            guard groups.count > 1, let group = groups.first(where: { $0.id == groupId }) ?? groups.first else { return self }
            return Content(groups: [group])
        }

        /// État de la livraison : le premier lieu où quelque chose est arrivé, sinon « en route » si une commande
        /// est fermée ; nil tant que tout est encore ouvert (ou déjà récupéré).
        var arrival: Arrival? {
            if let place = places.first(where: { $0.items.contains(where: \.isReadyToPickUp) }) { return .arrived(place) }
            return items.contains(where: \.isOnTheWay) ? .onTheWay : nil
        }

        /// Le même contenu où ces commandes sont marquées récupérées (scan de l'hôte vu par `refreshPickups`).
        func markingPickedUp(_ groupOrderIds: Set<String>) -> Content {
            var copy = self
            for g in copy.groups.indices {
                for p in copy.groups[g].places.indices {
                    for i in copy.groups[g].places[p].items.indices
                    where groupOrderIds.contains(copy.groups[g].places[p].items[i].groupOrderId) {
                        copy.groups[g].places[p].items[i].isPickedUp = true
                        copy.groups[g].places[p].items[i].pickupCode = nil
                    }
                }
            }
            return copy
        }

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

    /// Retour samuel : pendant que le QR est affiché, relit (sans cache) la part du ménage de chaque commande à code
    /// et marque celles que l'hôte vient de scanner, pour enchaîner sur le remerciement. Aucun écouteur Firestore :
    /// une lecture de document par commande, seulement quand un code est à l'écran.
    func refreshPickups() async {
        guard let pending = state.value?.items.filter({ !$0.isPickedUp && $0.pickupCode != nil }), !pending.isEmpty else { return }
        var picked: Set<String> = []
        for item in pending {
            if let share = try? await repositories.groupOrders.share(ofHousehold: householdId, inGroupOrder: item.groupOrderId),
               share.isPickedUp {
                picked.insert(item.groupOrderId)
            }
        }
        guard !picked.isEmpty, let current = state.value else { return }
        state = .loaded(current.markingPickedUp(picked))
    }

    nonisolated private static func content(
        householdId: String, groupId: String, userId: String, repositories: AppRepositories
    ) async throws -> Content? {
        // Noms des membres (« Récupéré par Amina ») : un détail, jamais bloquant.
        let household = try? await repositories.users.household(id: householdId)
        // Toutes les parts du ménage, dans tous ses groupes : une part réservée dans un autre groupe que le groupe
        // actif apparaît aussi. Le groupe actif d'abord (son point de cueillette passe en premier).
        let (orders, groupNames) = try await activeOrders(householdId: householdId, activeGroupId: groupId,
                                                          repositories: repositories)
        var entries: [Entry] = []
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
            // Une commande livrée et récupérée depuis longtemps n'a plus rien à faire ici.
            guard !isLongDone(order: order, share: share) else { continue }
            // Sécurité : le code porte le jeton privé du ménage (créé au besoin, `pickupCode`), jamais dérivé des
            // ids publics. Seulement à partir de la clôture ; sans réseau, l'hôte confirme à la main (« Récupéré »).
            let code = (order.status == .closed || order.status == .delivered) && !share.isPickedUp
                ? try? await repositories.groupOrders.pickupCode(householdId: householdId, groupOrderId: order.id)
                : nil
            let item = Item(groupOrderId: order.id, product: product, offer: offer, quantity: share.quantity,
                            totalCents: price * share.quantity, isPickedUp: share.isPickedUp,
                            pickedUpByName: share.pickedUpBy.flatMap { HouseholdMembership.firstName(of: $0, in: household) },
                            orderStatus: order.status,
                            pickupCode: qrPayload(for: order, code: code, memberId: userId))
            entries.append(Entry(item: item, pickupPointId: PickupPoint.resolvedId(for: order, in: allPoints),
                                 slots: order.pickupSlots, groupId: order.groupId))
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
        return Content(groups: groups(from: entries, points: points, hostFirstNames: hostFirstNames, groupNames: groupNames))
    }

    /// Contenu du QR d'UNE commande : le code de la part du ménage (`GroupOrderRepository.pickupCode`, jeton privé,
    /// le même pour tous ses membres), suivi du membre qui le montre. nil tant que la commande n'est pas fermée ou
    /// sans code à jeton : pas de faux QR. L'ancien `share.qrCode` (dérivé des ids, refusé au scan) n'est jamais lu.
    nonisolated static func qrPayload(for order: GroupOrder, code: String?, memberId: String) -> String? {
        guard order.status == .closed || order.status == .delivered,
              let code = code?.trimmingCharacters(in: .whitespacesAndNewlines),
              let parsed = PickupDesk.parse(code), !parsed.isLegacy else { return nil }
        return PickupDesk.memberCode(code, memberId: memberId)
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

    /// T-198 : une section par groupe, dans l'ordre où il apparaît (groupe actif d'abord), chacune rangée par lieu.
    nonisolated static func groups(
        from entries: [Entry], points: [String: PickupPoint], hostFirstNames: [String: String] = [:],
        groupNames: [String: String] = [:], now: Date = .now
    ) -> [GroupPickup] {
        var order: [String] = []
        var grouped: [String: [Entry]] = [:]
        for entry in entries {
            if grouped[entry.groupId] == nil { order.append(entry.groupId) }
            grouped[entry.groupId, default: []].append(entry)
        }
        return order.map { groupId in
            GroupPickup(groupId: groupId, groupName: groupNames[groupId],
                        places: places(from: grouped[groupId] ?? [], points: points, hostFirstNames: hostFirstNames, now: now))
        }
    }

    /// Délai pendant lequel une part récupérée d'une commande livrée reste affichée (« Tout est récupéré »).
    nonisolated static let doneRetention: TimeInterval = 2 * 86_400

    /// Commande livrée dont la part est récupérée depuis plus de `doneRetention` (ou sans date de remise).
    nonisolated static func isLongDone(order: GroupOrder, share: Share, now: Date = .now) -> Bool {
        guard order.status == .delivered, share.isPickedUp else { return false }
        guard let pickedUpAt = share.pickedUpAt else { return true }
        return now.timeIntervalSince(pickedUpAt) > doneRetention
    }

    /// Commandes non annulées des groupes du ménage (livrées comprises : c'est là qu'on vient chercher sa part),
    /// celles du groupe actif d'abord, et le nom de chaque groupe.
    /// La liste des groupes est un détail : si elle échoue, on garde au moins le groupe actif.
    nonisolated static func activeOrders(
        householdId: String, activeGroupId: String, repositories: AppRepositories
    ) async throws -> (orders: [GroupOrder], groupNames: [String: String]) {
        let memberGroups = (try? await repositories.groups.groups(ofHousehold: householdId)) ?? []
        var groupNames = Dictionary(memberGroups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        if groupNames[activeGroupId] == nil, let active = try? await repositories.groups.group(id: activeGroupId) {
            groupNames[activeGroupId] = active.name
        }
        let memberGroupIds = memberGroups.map(\.id)
        let groupIds = [activeGroupId] + memberGroupIds.filter { $0 != activeGroupId }
        var orders: [GroupOrder] = []
        var seen = Set<String>()
        for groupId in groupIds {
            for order in try await repositories.groupOrders.groupOrders(ofGroup: groupId)
            where order.status != .cancelled && seen.insert(order.id).inserted {
                orders.append(order)
            }
        }
        return (orders, groupNames)
    }
}
