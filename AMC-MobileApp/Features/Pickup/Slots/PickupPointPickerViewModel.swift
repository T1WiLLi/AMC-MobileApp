// PickupPointPickerViewModel.swift
// RQ-063 (T-077) : le coordonnateur choisit le point de cueillette d'une commande et ses créneaux.

import Foundation
import Observation

@Observable
@MainActor
final class PickupPointPickerViewModel {
    nonisolated struct Content: Sendable, Hashable {
        var order: GroupOrder
        var group: NeighborhoodGroup
        var points: [PickupPoint]
        /// Ménages qui ont déjà réservé un créneau (prévenus si on retire leur créneau).
        var reservedHouseholds: Int
        var isCoordinator: Bool
    }

    private(set) var state: LoadState<Content> = .idle
    private(set) var selectedPointId: String?
    /// Créneaux en cours d'édition, triés.
    private(set) var slots: [PickupSlot] = []
    private(set) var isSaving = false
    private(set) var saveError: AppError?
    /// Commande enregistrée au dernier `save()` réussi.
    private(set) var savedOrder: GroupOrder?

    static let defaultSlotDuration: TimeInterval = 3_600
    static let defaultSlotCapacity = 8

    private let repositories: AppRepositories
    private let userId: String
    private let groupOrderId: String
    private let now: @Sendable () -> Date

    init(repositories: AppRepositories, userId: String, groupOrderId: String,
         now: @escaping @Sendable () -> Date = { .now }) {
        self.repositories = repositories
        self.userId = userId
        self.groupOrderId = groupOrderId
        self.now = now
    }

    var selectedPoint: PickupPoint? {
        state.value?.points.first { $0.id == selectedPointId }
    }

    var validationError: AppError? {
        guard selectedPointId != nil else { return .invalidInput(String(localized: "Choisis un point de cueillette.")) }
        guard !slots.isEmpty else { return .invalidInput(String(localized: "Ajoute au moins un créneau.")) }
        do {
            _ = try PickupSlotBook.validatedSlots(slots)
            return nil
        } catch let error as AppError {
            return error
        } catch {
            return AppError(error)
        }
    }

    var hasChanges: Bool {
        guard let order = state.value?.order else { return false }
        return order.pickupPointId != selectedPointId || order.pickupSlots != slots
    }

    var canSave: Bool {
        state.value?.isCoordinator == true && validationError == nil && hasChanges && !isSaving
    }

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, groupOrderId = groupOrderId, userId = userId
        do {
            let order = try await repositories.groupOrders.groupOrder(id: groupOrderId)
            async let group = repositories.groups.group(id: order.groupId)
            async let points = repositories.pickupPoints.pickupPoints()
            async let shares = repositories.groupOrders.shares(ofGroupOrder: groupOrderId)
            let (loadedGroup, loadedPoints, loadedShares) = try await (group, points, shares)
            let content = Content(
                order: order, group: loadedGroup, points: loadedPoints,
                reservedHouseholds: loadedShares.filter { $0.pickupSlotStart != nil }.count,
                isCoordinator: loadedGroup.coordinatorIds.contains(userId)
            )
            state = .loaded(content)
            selectedPointId = order.pickupPointId
            slots = order.pickupSlots.sorted { $0.start < $1.start }
            // Pas encore de point : la zone de livraison du groupe (créée avec lui) est proposée par défaut.
            if order.pickupPointId == nil, let zone = PickupPoint.deliveryZone(ofGroup: order.groupId, in: loadedPoints) {
                selectPoint(id: zone.id)
            }
        } catch {
            state = .failed(AppError(error))
        }
    }

    /// Choisit un point ; reprend ses créneaux à venir si la commande n'en a pas encore.
    func selectPoint(id: String) {
        guard let point = state.value?.points.first(where: { $0.id == id }) else { return }
        selectedPointId = id
        if slots.isEmpty {
            slots = point.slots.filter { $0.end > now() }.sorted { $0.start < $1.start }
        }
    }

    /// Ajoute un créneau d'une heure juste après le dernier (ou samedi prochain à 10 h).
    func addSlot() {
        let start = slots.last?.end ?? Self.nextSaturdayMorning(after: now())
        slots.append(PickupSlot(start: start, end: start.addingTimeInterval(Self.defaultSlotDuration),
                                capacity: Self.defaultSlotCapacity))
    }

    func removeSlot(start: Date) {
        slots.removeAll { $0.start == start }
    }

    /// Change l'heure de début en gardant la durée.
    func moveSlot(start: Date, to newStart: Date) {
        guard let index = slots.firstIndex(where: { $0.start == start }) else { return }
        let duration = slots[index].end.timeIntervalSince(slots[index].start)
        slots[index].start = newStart
        slots[index].end = newStart.addingTimeInterval(duration)
        slots.sort { $0.start < $1.start }
    }

    func setDuration(start: Date, minutes: Int) {
        guard let index = slots.firstIndex(where: { $0.start == start }) else { return }
        slots[index].end = slots[index].start.addingTimeInterval(Double(max(15, minutes)) * 60)
    }

    func setCapacity(start: Date, capacity: Int?) {
        guard let index = slots.firstIndex(where: { $0.start == start }) else { return }
        slots[index].capacity = capacity.map { min(max(1, $0), PickupSlotBook.maxSlotCapacity) }
    }

    @discardableResult
    func save() async -> GroupOrder? {
        guard canSave, var content = state.value else { return nil }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let order = try await repositories.groupOrders.setPickupPoint(
                selectedPointId, slots: slots, groupOrderId: groupOrderId
            )
            content.order = order
            state = .loaded(content)
            slots = order.pickupSlots
            savedOrder = order
            return order
        } catch {
            saveError = AppError(error)
            return nil
        }
    }

    nonisolated static func nextSaturdayMorning(after date: Date, calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.weekday = 7
        components.hour = 10
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime) ?? date
    }
}
