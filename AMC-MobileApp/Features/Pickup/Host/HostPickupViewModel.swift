// HostPickupViewModel.swift
// T-181 : l'hôte d'un point de cueillette remet les parts : liste des ménages à servir (par commande et par
// créneau), « Récupéré » d'un tap, ou scan du code QR de la famille. Réutilise `PickupDesk` (T-043 / T-159) :
// une part par ménage, remise une seule fois, transaction côté `confirmPickup`.

import Foundation
import Observation

@Observable
@MainActor
final class HostPickupViewModel {
    /// Une commande à remettre chez cet hôte.
    nonisolated struct Station: Identifiable, Sendable, Equatable {
        var order: GroupOrder
        var pointName: String
        var productName: String
        var shares: [Share]
        var displayNames: [String: String]

        var id: String { order.id }

        /// Créneaux réservés par les ménages, du plus tôt au plus tard.
        var slots: [Date] {
            Array(Set(shares.filter { $0.quantity > 0 }.compactMap(\.pickupSlotStart))).sorted()
        }

        /// Liste de distribution, éventuellement limitée à un créneau.
        func checklist(slot: Date?) -> PickupDesk.Checklist {
            let visible = slot.map { slot in shares.filter { $0.pickupSlotStart == slot } } ?? shares
            return PickupDesk.checklist(shares: visible, displayNames: displayNames)
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
    }

    private(set) var state: LoadState<Content> = .idle
    /// Commande affichée ; la première par défaut.
    var selectedOrderId: String?
    /// Créneau filtré ; nil = tous.
    var selectedSlot: Date?
    private(set) var outcome: Outcome?
    private(set) var pendingHouseholdId: String?
    private(set) var actionError: AppError?
    /// Compte les remises réussies (déclenche l'haptique de succès).
    private(set) var successes = 0
    /// Compte les refus (déclenche l'haptique d'avertissement).
    private(set) var rejections = 0

    private let repositories: AppRepositories
    private let userId: String
    private let householdId: String
    private let groupId: String?
    private let now: @Sendable () -> Date

    init(repositories: AppRepositories, userId: String, householdId: String, groupId: String?,
         now: @escaping @Sendable () -> Date = { .now }) {
        self.repositories = repositories
        self.userId = userId
        self.householdId = householdId
        self.groupId = groupId
        self.now = now
    }

    var selectedStation: Station? {
        guard let content = state.value else { return nil }
        return content.stations.first { $0.id == selectedOrderId } ?? content.stations.first
    }

    var checklist: PickupDesk.Checklist? { selectedStation?.checklist(slot: selectedSlot) }

    func selectOrder(_ id: String) {
        selectedOrderId = id
        selectedSlot = nil
    }

    func dismissOutcome() { outcome = nil }
    func dismissError() { actionError = nil }

    // MARK: Chargement

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, userId = userId, householdId = householdId, groupId = groupId
        do {
            let stations = try await Self.stations(repositories: repositories, userId: userId,
                                                   householdId: householdId, groupId: groupId)
            state = stations.isEmpty ? .empty : .loaded(Content(stations: stations))
            if let current = selectedOrderId, !stations.contains(where: { $0.id == current }) { selectedOrderId = nil }
        } catch {
            if state.value == nil { state = .failed(AppError(error)) } else { actionError = AppError(error) }
        }
    }

    /// Commandes fermées ou livrées dont le point de cueillette est celui de l'hôte.
    nonisolated static func stations(
        repositories: AppRepositories, userId: String, householdId: String, groupId: String?
    ) async throws -> [Station] {
        let points = try await repositories.pickupPoints.pickupPoints().filter { $0.hostUserId == userId }
        guard !points.isEmpty else { return [] }
        var groupIds = Set((try? await repositories.groups.groups(ofHousehold: householdId))?.map(\.id) ?? [])
        if let groupId { groupIds.insert(groupId) }

        var stations: [Station] = []
        for gid in groupIds.sorted() {
            let orders = (try? await repositories.groupOrders.groupOrders(ofGroup: gid)) ?? []
            for order in orders where PickupDesk.canPickUp(order.status) {
                guard let point = points.first(where: { $0.id == order.pickupPointId }) else { continue }
                let shares = try await repositories.groupOrders.shares(ofGroupOrder: order.id).filter { $0.quantity > 0 }
                guard !shares.isEmpty else { continue }
                var productName = String(localized: "Commande groupée")
                if let offer = try? await repositories.offers.offer(id: order.offerId),
                   let product = try? await repositories.vendors.product(id: offer.productId) {
                    productName = product.name
                }
                var names: [String: String] = [:]
                for share in shares {
                    if let household = try? await repositories.users.household(id: share.householdId) {
                        names[share.householdId] = household.name
                    }
                }
                stations.append(Station(order: order, pointName: point.name, productName: productName,
                                        shares: shares, displayNames: names))
            }
        }
        return stations.sorted { ($0.order.pickupSlots.first?.start ?? .distantFuture, $0.id)
            < ($1.order.pickupSlots.first?.start ?? .distantFuture, $1.id) }
    }

    // MARK: Remise

    /// Un tap sur « Récupéré » : même chemin que le scan, avec le code du ménage (transaction côté dépôt).
    func markPickedUp(householdId: String, in orderId: String) async {
        guard pendingHouseholdId == nil else { return }
        pendingHouseholdId = householdId
        defer { pendingHouseholdId = nil }
        let code = ShareAllocator.qrCode(orderId: orderId, householdId: householdId)
        await confirm(code: code, orderId: orderId)
    }

    /// Code lu par la caméra. La commande est celle du code si l'hôte la sert, sinon la commande affichée
    /// (le dépôt répond alors « mauvaise commande »).
    func scan(_ rawCode: String) async {
        guard pendingHouseholdId == nil, let content = state.value else { return }
        let qr = PickupDesk.splitMemberCode(rawCode).qrCode
        let parts = qr.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let codeOrderId = parts.count == 4 && parts[0] == "GRENIER" ? parts[1] : nil
        let target = content.stations.first { $0.id == codeOrderId } ?? selectedStation
        guard let target else { return }
        if target.id != selectedOrderId { selectOrder(target.id) }
        await confirm(code: rawCode, orderId: target.id)
    }

    private func confirm(code: String, orderId: String) async {
        do {
            let result = try await repositories.groupOrders.confirmPickup(code: code, groupOrderId: orderId, at: now())
            if let share = result.share { apply(share, to: orderId) }
            var householdName: String?
            if let share = result.share {
                householdName = state.value?.stations.first { $0.id == orderId }?.displayNames[share.householdId]
                    ?? String(localized: "Ménage \(share.householdId)")
            }
            outcome = Outcome(result: result, householdName: householdName)
            if result.isSuccess { successes += 1 } else { rejections += 1 }
        } catch {
            actionError = AppError(error)
            rejections += 1
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
