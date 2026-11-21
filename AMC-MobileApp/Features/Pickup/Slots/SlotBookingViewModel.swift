// SlotBookingViewModel.swift
// RQ-064 (T-077) : un ménage réserve son créneau de cueillette, avec les places restantes.

import Foundation
import Observation

@Observable
@MainActor
final class SlotBookingViewModel {
    nonisolated struct Content: Sendable, Hashable {
        var order: GroupOrder
        var pickupPoint: PickupPoint?
        var availability: [PickupSlotBook.Availability]
        /// Part du ménage ; nil s'il n'a rien réservé dans ce lot.
        var myShare: Share?

        var reservedStart: Date? { myShare?.pickupSlotStart }
    }

    /// `.empty` quand le coordonnateur n'a encore proposé aucun créneau.
    private(set) var state: LoadState<Content> = .idle
    /// Créneau en cours d'envoi (pour l'indicateur sur la bonne carte).
    private(set) var pendingStart: Date?
    private(set) var actionError: AppError?
    /// Augmente à chaque réservation confirmée (haptique de succès).
    private(set) var confirmations = 0

    private let repositories: AppRepositories
    private let householdId: String
    private let groupOrderId: String
    private let now: @Sendable () -> Date

    init(repositories: AppRepositories, householdId: String, groupOrderId: String,
         now: @escaping @Sendable () -> Date = { .now }) {
        self.repositories = repositories
        self.householdId = householdId
        self.groupOrderId = groupOrderId
        self.now = now
    }

    var isSaving: Bool { pendingStart != nil }

    /// Un créneau se choisit s'il n'est ni passé, ni complet (sauf le sien), et que le ménage a une part.
    func canReserve(_ availability: PickupSlotBook.Availability) -> Bool {
        guard let content = state.value, content.myShare != nil, !isSaving else { return false }
        if content.reservedStart == availability.slot.start { return false }
        return availability.slot.end > now() && !availability.isFull
    }

    func isPast(_ availability: PickupSlotBook.Availability) -> Bool { availability.slot.end <= now() }

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, groupOrderId = groupOrderId, householdId = householdId
        do {
            let order = try await repositories.groupOrders.groupOrder(id: groupOrderId)
            let shares = try await repositories.groupOrders.shares(ofGroupOrder: groupOrderId)
            var point: PickupPoint?
            if let pointId = order.pickupPointId {
                point = try? await repositories.pickupPoints.pickupPoint(id: pointId)
            }
            guard !order.pickupSlots.isEmpty else {
                state = .empty
                return
            }
            state = .loaded(Content(
                order: order, pickupPoint: point,
                availability: PickupSlotBook.availability(of: order.pickupSlots, shares: shares),
                myShare: shares.first { $0.householdId == householdId }
            ))
        } catch {
            state = .failed(AppError(error))
        }
    }

    func reserve(_ start: Date) async { await send(start) }

    func cancelReservation() async { await send(nil) }

    private func send(_ start: Date?) async {
        guard state.value != nil, !isSaving else { return }
        pendingStart = start ?? state.value?.reservedStart
        actionError = nil
        defer { pendingStart = nil }
        do {
            try await repositories.groupOrders.reservePickupSlot(
                start: start, householdId: householdId, groupOrderId: groupOrderId
            )
            await load()
            if start != nil { confirmations += 1 }
        } catch {
            actionError = AppError(error)
            await load()
        }
    }
}
