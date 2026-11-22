// HostPickupViewModel.swift
// T-181 : l'hôte d'un point de cueillette remet les parts : liste des ménages à servir (par commande et par
// créneau), « Récupéré » d'un tap, ou scan du code QR de la famille. Réutilise `PickupDesk` (T-043 / T-159) :
// une part par ménage, remise une seule fois, transaction côté `confirmPickup`.
// « La livraison est arrivée » : l'hôte du point ou un coordonnateur du groupe marque la commande fermée comme
// arrivée (`OrderArrival`) ; la remise ne commence qu'ensuite, et les familles sont prévenues dans leur app.

import Foundation
import Observation

@Observable
@MainActor
final class HostPickupViewModel {
    /// Une commande à remettre chez cet hôte (ou dans un groupe que l'utilisateur coordonne).
    nonisolated struct Station: Identifiable, Sendable, Equatable {
        var order: GroupOrder
        /// Point de cueillette de la commande, nil s'il n'est pas encore choisi (coordonnateur seulement).
        var point: PickupPoint?
        var productName: String
        /// Format d'une part (« sac de 10 kg »), nil si le lot est illisible.
        var unit: String?
        var vendorName: String?
        var groupName: String?
        var shares: [Share]
        /// Nom affiché de chaque ménage (`ShareHouseholdName.display`), pour toutes les parts.
        var displayNames: [String: String]
        /// Prénom du membre qui a récupéré la part, quand il est lisible.
        var pickedUpByNames: [String: String] = [:]
        /// L'utilisateur peut marquer la livraison comme arrivée (hôte du point ou coordonnateur du groupe).
        var canMarkArrived: Bool = true

        var id: String { order.id }

        var pointName: String { point?.name ?? String(localized: "Point à choisir") }

        /// En route, remise en cours ou terminée.
        var stage: OrderArrival.Stage {
            OrderArrival.stage(of: order.status, allPickedUp: !shares.isEmpty && shares.allSatisfy(\.isPickedUp))
                ?? .enRoute
        }

        /// Les parts se remettent seulement une fois la livraison arrivée.
        var isArrived: Bool { PickupDesk.canPickUp(order.status) }

        /// Créneaux réservés par les ménages, du plus tôt au plus tard.
        var slots: [Date] {
            Array(Set(shares.filter { $0.quantity > 0 }.compactMap(\.pickupSlotStart))).sorted()
        }

        /// Liste de distribution, éventuellement limitée à un créneau.
        func checklist(slot: Date?) -> PickupDesk.Checklist {
            let visible = slot.map { slot in shares.filter { $0.pickupSlotStart == slot } } ?? shares
            return PickupDesk.checklist(shares: visible, displayNames: displayNames)
        }

        /// Familles à servir et servies, filtrées par créneau et par la recherche.
        func board(slot: Date?, query: String = "") -> Board {
            Board(shares: shares, displayNames: displayNames, pickedUpByNames: pickedUpByNames,
                  slot: slot, query: query)
        }
    }

    /// Remise d'une commande : « À servir » / « Servis », et les compteurs (familles et parts).
    nonisolated struct Board: Sendable, Equatable {
        nonisolated struct Row: Identifiable, Sendable, Equatable {
            var householdId: String
            var name: String
            var quantity: Int
            var isPaid: Bool
            var isPickedUp: Bool
            var pickedUpAt: Date?
            var pickedUpByName: String?
            var slotStart: Date?

            var id: String { householdId }
        }

        /// À servir : par créneau réservé (les sans créneau à la fin), puis par nom.
        var toServe: [Row]
        /// Servis : les plus récents d'abord.
        var served: [Row]
        /// Compteurs du créneau affiché (la recherche ne les change pas).
        var familiesTotal: Int
        var familiesServed: Int
        var sharesTotal: Int
        var sharesHanded: Int

        var isEmpty: Bool { familiesTotal == 0 }
        var isComplete: Bool { familiesTotal > 0 && familiesServed == familiesTotal }
        var familiesProgress: Double { familiesTotal == 0 ? 0 : Double(familiesServed) / Double(familiesTotal) }
        var sharesProgress: Double { sharesTotal == 0 ? 0 : Double(sharesHanded) / Double(sharesTotal) }

        init(shares: [Share], displayNames: [String: String], pickedUpByNames: [String: String] = [:],
             slot: Date? = nil, query: String = "") {
            let inSlot = shares.filter { $0.quantity > 0 && (slot == nil || $0.pickupSlotStart == slot) }
            let rows = inSlot.map { share in
                Row(householdId: share.householdId,
                    name: displayNames[share.householdId]
                        ?? ShareHouseholdName.display(householdId: share.householdId, householdName: share.householdName),
                    quantity: share.quantity, isPaid: share.isPaid, isPickedUp: share.isPickedUp,
                    pickedUpAt: share.pickedUpAt, pickedUpByName: pickedUpByNames[share.householdId],
                    slotStart: share.pickupSlotStart)
            }
            familiesTotal = rows.count
            familiesServed = rows.filter(\.isPickedUp).count
            sharesTotal = rows.reduce(0) { $0 + $1.quantity }
            sharesHanded = rows.filter(\.isPickedUp).reduce(0) { $0 + $1.quantity }

            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let visible = query.isEmpty ? rows : rows.filter { $0.name.localizedStandardContains(query) }
            toServe = visible.filter { !$0.isPickedUp }.sorted { left, right in
                let l = left.slotStart ?? .distantFuture, r = right.slotStart ?? .distantFuture
                if l != r { return l < r }
                let byName = left.name.localizedStandardCompare(right.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return left.householdId < right.householdId
            }
            served = visible.filter(\.isPickedUp).sorted { left, right in
                let l = left.pickedUpAt ?? .distantPast, r = right.pickedUpAt ?? .distantPast
                if l != r { return l > r }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
        }
    }

    nonisolated struct Content: Sendable, Equatable {
        var stations: [Station]
    }

    /// Dernier code scanné ou tapé : le résultat s'affiche en bandeau.
    nonisolated struct Outcome: Identifiable, Sendable, Equatable {
        let id = UUID()
        var result: PickupDesk.ScanResult
        var householdName: String?
        /// T-198 : autres commandes du même QR de groupe remises en même temps.
        var otherOrdersHandedOver: Int = 0

        /// « Aussi remis : 2 autres commandes de ce groupe. », nil s'il n'y en a pas.
        var othersMessage: String? {
            switch otherOrdersHandedOver {
            case 0: nil
            case 1: String(localized: "Aussi remise : 1 autre commande de ce groupe.")
            default: String(localized: "Aussi remises : \(otherOrdersHandedOver) autres commandes de ce groupe.")
            }
        }
    }

    /// Au-delà de ce nombre de familles, un champ de recherche apparaît.
    nonisolated static let searchThreshold = 8
    /// Une commande entièrement remise reste affichée ce temps-là après la dernière remise.
    nonisolated static let finishedRetention: TimeInterval = 2 * 86_400

    private(set) var state: LoadState<Content> = .idle
    /// Commande affichée ; la première par défaut.
    var selectedOrderId: String?
    /// Créneau filtré ; nil = tous.
    var selectedSlot: Date?
    /// Recherche d'une famille par son nom.
    var searchText = ""
    private(set) var outcome: Outcome?
    private(set) var pendingHouseholdId: String?
    private(set) var actionError: AppError?
    /// Compte les remises réussies (déclenche l'haptique de succès).
    private(set) var successes = 0
    /// Compte les refus (déclenche l'haptique d'avertissement).
    private(set) var rejections = 0
    /// Commande en train d'être marquée comme arrivée.
    private(set) var arrivingOrderId: String?
    /// Compte les arrivées enregistrées (haptique et bandeau « Arrivée enregistrée »).
    private(set) var arrivals = 0
    /// Commande dont l'arrivée vient d'être enregistrée (bandeau de confirmation).
    private(set) var arrivedOrderId: String?

    private let repositories: AppRepositories
    private let userId: String
    private let householdId: String
    private let groupId: String?
    /// Limite l'écran aux commandes de ce groupe (ouvert depuis la fiche du groupe).
    private let focusGroupId: String?
    private let now: @Sendable () -> Date

    init(repositories: AppRepositories, userId: String, householdId: String, groupId: String?,
         focusGroupId: String? = nil, now: @escaping @Sendable () -> Date = { .now }) {
        self.repositories = repositories
        self.userId = userId
        self.householdId = householdId
        self.groupId = groupId
        self.focusGroupId = focusGroupId
        self.now = now
    }

    var selectedStation: Station? {
        guard let content = state.value else { return nil }
        return content.stations.first { $0.id == selectedOrderId } ?? content.stations.first
    }

    var checklist: PickupDesk.Checklist? { selectedStation?.checklist(slot: selectedSlot) }

    var board: Board? { selectedStation?.board(slot: selectedSlot, query: searchText) }

    /// Le champ de recherche n'apparaît que s'il y a beaucoup de familles.
    var showsSearch: Bool { (selectedStation?.shares.count ?? 0) > Self.searchThreshold }

    func selectOrder(_ id: String) {
        selectedOrderId = id
        selectedSlot = nil
        searchText = ""
    }

    func dismissOutcome() { outcome = nil }
    func dismissError() { actionError = nil }
    func dismissArrivalNotice() { arrivedOrderId = nil }

    // MARK: Chargement

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, userId = userId, householdId = householdId, groupId = groupId
        let focusGroupId = focusGroupId, now = now()
        do {
            let stations = try await Self.stations(repositories: repositories, userId: userId,
                                                   householdId: householdId, groupId: groupId,
                                                   focusGroupId: focusGroupId, now: now)
            state = stations.isEmpty ? .empty : .loaded(Content(stations: stations))
            if let current = selectedOrderId, !stations.contains(where: { $0.id == current }) { selectedOrderId = nil }
        } catch {
            if state.value == nil { state = .failed(AppError(error)) } else { actionError = AppError(error) }
        }
    }

    /// Commandes fermées (en route) ou livrées (remise) dont l'utilisateur est l'hôte du point ou un coordonnateur
    /// du groupe. Les remises en cours d'abord, puis les livraisons en route, puis les remises terminées.
    nonisolated static func stations(
        repositories: AppRepositories, userId: String, householdId: String, groupId: String?,
        focusGroupId: String? = nil, now: Date = .now
    ) async throws -> [Station] {
        let points = try await repositories.pickupPoints.pickupPoints()
        var groups = (try? await repositories.groups.groups(ofHousehold: householdId)) ?? []
        // T-203 : un hôte n'est pas forcément membre du groupe qui livre à son point (compte « hôte » seul) :
        // on ajoute les groupes des points qu'il accueille, sinon il voyait « Rien à remettre ».
        let hostedGroupIds = points.filter { $0.hostUserId == userId }.compactMap(\.groupId)
        for extra in [groupId, focusGroupId].compactMap({ $0 }) + hostedGroupIds
        where !groups.contains(where: { $0.id == extra }) {
            if let group = try? await repositories.groups.group(id: extra) { groups.append(group) }
        }
        if let focusGroupId { groups = groups.filter { $0.id == focusGroupId } }
        let hostsAPoint = points.contains { $0.hostUserId == userId }
        guard hostsAPoint || groups.contains(where: { $0.coordinatorIds.contains(userId) }) else { return [] }

        var stations: [Station] = []
        for group in groups.sorted(by: { $0.id < $1.id }) {
            let orders = (try? await repositories.groupOrders.groupOrders(ofGroup: group.id)) ?? []
            for order in orders where order.status == .closed || order.status == .delivered {
                let point = points.first { $0.id == order.pickupPointId }
                let allowed = OrderArrival.isAllowed(userId: userId, coordinatorIds: group.coordinatorIds,
                                                     pointHostUserId: point?.hostUserId)
                guard allowed else { continue }
                let shares = try await repositories.groupOrders.shares(ofGroupOrder: order.id).filter { $0.quantity > 0 }
                guard !shares.isEmpty, !isLongFinished(order: order, shares: shares, now: now) else { continue }
                stations.append(await station(order: order, point: point, group: group, shares: shares,
                                              repositories: repositories))
            }
        }
        return stations.sorted { left, right in
            let l = rank(left.stage), r = rank(right.stage)
            if l != r { return l < r }
            return (left.order.pickupSlots.first?.start ?? .distantFuture, left.id)
                < (right.order.pickupSlots.first?.start ?? .distantFuture, right.id)
        }
    }

    private nonisolated static func rank(_ stage: OrderArrival.Stage) -> Int {
        switch stage {
        case .handingOut: 0
        case .enRoute: 1
        case .finished: 2
        }
    }

    /// Livrée, tout remis, et la dernière remise date de plus de `finishedRetention` : plus rien à faire ici.
    nonisolated static func isLongFinished(order: GroupOrder, shares: [Share], now: Date) -> Bool {
        guard order.status == .delivered, !shares.isEmpty, shares.allSatisfy(\.isPickedUp) else { return false }
        guard let last = (shares.compactMap(\.pickedUpAt) + [order.deliveredAt].compactMap { $0 }).max() else { return true }
        return now.timeIntervalSince(last) > finishedRetention
    }

    private nonisolated static func station(
        order: GroupOrder, point: PickupPoint?, group: NeighborhoodGroup, shares: [Share], repositories: AppRepositories
    ) async -> Station {
        var productName = String(localized: "Commande groupée")
        var unit: String?
        var vendorName: String?
        if let offer = try? await repositories.offers.offer(id: order.offerId) {
            unit = offer.displayShareUnit
            if let product = try? await repositories.vendors.product(id: offer.productId) { productName = product.name }
            vendorName = (try? await repositories.vendors.vendor(id: offer.vendorId))?.legalName
        }
        var names: [String: String] = [:]
        var pickedUpBy: [String: String] = [:]
        for share in shares {
            // Le nom copié dans la part d'abord : l'hôte ne peut pas lire `households/{id}` (membres seulement).
            let known = ShareHouseholdName.normalized(share.householdName) != nil
                ? nil : (try? await repositories.users.household(id: share.householdId))?.name
            names[share.householdId] = ShareHouseholdName.display(
                householdId: share.householdId, householdName: share.householdName, known: known)
            if share.isPickedUp, let memberId = share.pickedUpBy,
               let member = try? await repositories.users.user(id: memberId),
               let first = member.displayName.split(separator: " ").first {
                pickedUpBy[share.householdId] = String(first)
            }
        }
        return Station(order: order, point: point, productName: productName, unit: unit, vendorName: vendorName,
                       groupName: group.name, shares: shares, displayNames: names, pickedUpByNames: pickedUpBy)
    }

    // MARK: Arrivée

    /// « Marquer comme arrivée » : la commande passe de fermée à livrée, la remise peut commencer.
    func markArrived(orderId: String) async {
        guard arrivingOrderId == nil, let station = state.value?.stations.first(where: { $0.id == orderId }),
              station.canMarkArrived, OrderArrival.canMark(station.order) else { return }
        arrivingOrderId = orderId
        defer { arrivingOrderId = nil }
        do {
            let delivered = try await repositories.groupOrders.markArrived(groupOrderId: orderId, at: now())
            guard var content = state.value,
                  let index = content.stations.firstIndex(where: { $0.id == orderId }) else { return }
            content.stations[index].order = delivered
            state = .loaded(content)
            arrivedOrderId = orderId
            arrivals += 1
        } catch {
            actionError = AppError(error)
            rejections += 1
        }
    }

// MARK: Remise

    /// Un tap sur « Récupéré » : l'hôte a reconnu la famille, sans code (`confirmPickupByHand`, transaction côté
    /// dépôt). C'est aussi le recours pour un ancien code ou une famille qui n'a pas l'app à jour.
    func markPickedUp(householdId: String, in orderId: String) async {
        guard pendingHouseholdId == nil else { return }
        pendingHouseholdId = householdId
        defer { pendingHouseholdId = nil }
        let repositories = repositories, userId = userId, date = now()
        await confirm(orderId: orderId) {
            try await repositories.groupOrders.confirmPickupByHand(
                householdId: householdId, groupOrderId: orderId, confirmedBy: userId, at: date
            )
        }
    }

    /// Code lu par la caméra. La commande est celle du code si l'hôte la sert, sinon la commande affichée
    /// (le dépôt répond alors « mauvaise commande »).
    /// T-198 : le QR d'un groupe porte le code de chaque commande du ménage ; un seul scan remet toutes celles que
    /// l'hôte sert. La commande affichée passe en dernier : c'est son résultat que montre le bandeau.
    func scan(_ rawCode: String) async {
        guard pendingHouseholdId == nil, let content = state.value else { return }
        let codes = PickupDesk.bundledCodes(rawCode)
        var targets: [(station: Station, code: String)] = []
        for code in codes {
            guard let orderId = PickupDesk.parse(code)?.orderId,
                  let station = content.stations.first(where: { $0.id == orderId }),
                  !targets.contains(where: { $0.station.id == orderId }) else { continue }
            targets.append((station, code))
        }
        if targets.isEmpty {
            guard let selectedStation else { return }
            targets = [(selectedStation, codes.first ?? rawCode)]
        }
        let shown = targets.first { $0.station.id == selectedOrderId } ?? targets[0]
        if shown.station.id != selectedOrderId { selectOrder(shown.station.id) }
        let others = targets.filter { $0.station.id != shown.station.id }
        var othersHandedOver = 0
        for target in others + [shown] {
            // Un code sans membre : l'hôte qui scanne est noté (firestore.rules exige `pickedUpBy`).
            let trimmed = target.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = PickupDesk.parse(trimmed)?.memberId == nil ? PickupDesk.memberCode(trimmed, memberId: userId) : trimmed
            let repositories = repositories, date = now(), orderId = target.station.id
            let isShown = orderId == shown.station.id
            let succeeded = await confirm(orderId: orderId, report: isShown, otherOrdersHandedOver: othersHandedOver) {
                try await repositories.groupOrders.confirmPickup(code: code, groupOrderId: orderId, at: date)
            }
            if !isShown && succeeded { othersHandedOver += 1 }
        }
    }

    /// Enregistre une remise. `report` faux : une autre commande du même QR de groupe, comptée sans bandeau.
    @discardableResult
    private func confirm(
        orderId: String, report: Bool = true, otherOrdersHandedOver: Int = 0,
        _ attempt: @Sendable () async throws -> PickupDesk.ScanResult
    ) async -> Bool {
        do {
            let result = try await attempt()
            if let share = result.share { apply(share, to: orderId) }
            guard report else { return result.isSuccess }
            var householdName: String?
            if let share = result.share {
                householdName = state.value?.stations.first { $0.id == orderId }?.displayNames[share.householdId]
                    ?? String(localized: "Ménage \(share.householdId)")
            }
            outcome = Outcome(result: result, householdName: householdName, otherOrdersHandedOver: otherOrdersHandedOver)
            if result.isSuccess || otherOrdersHandedOver > 0 { successes += 1 } else { rejections += 1 }
            return result.isSuccess
        } catch {
            if report {
                actionError = AppError(error)
                rejections += 1
            }
            return false
        }
    }

    private func apply(_ share: Share, to orderId: String) {
        guard var content = state.value,
              let index = content.stations.firstIndex(where: { $0.id == orderId }),
              let shareIndex = content.stations[index].shares.firstIndex(where: { $0.householdId == share.householdId })
        else { return }
        content.stations[index].shares[shareIndex] = share
        state = .loaded(content)
    }
}
