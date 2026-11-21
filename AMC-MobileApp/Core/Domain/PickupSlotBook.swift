// PickupSlotBook.swift
// Règles des points et créneaux de cueillette (T-077) en Swift pur, partagées par les fakes,
// Firestore et les ViewModels :
//   - RQ-062 : validation du point d'un hôte (nom, adresse, capacité) ;
//   - RQ-063 : créneaux choisis par le coordonnateur (ordre, chevauchement, capacité) ;
//   - RQ-064 : réservation d'un créneau par un ménage, places restantes.

import Foundation

nonisolated enum PickupSlotBook {
    /// Un créneau et ses réservations.
    struct Availability: Identifiable, Sendable, Hashable {
        var slot: PickupSlot
        /// Ménages qui ont réservé ce créneau.
        var reserved: Int

        var id: Date { slot.start }
        /// Places restantes ; nil = sans limite.
        var remaining: Int? { slot.capacity.map { max(0, $0 - reserved) } }
        var isFull: Bool { remaining == 0 }
        /// Taux de remplissage 0…1 ; nil sans limite.
        var fillRatio: Double? {
            guard let capacity = slot.capacity, capacity > 0 else { return nil }
            return min(1, Double(reserved) / Double(capacity))
        }
    }

    static let maxSlots = 20
    static let maxSlotCapacity = 500
    static let maxPointCapacity = 1_000
    static let nameLimit = 80
    static let addressLimit = 200

    // MARK: Point d'un hôte (RQ-062)

    /// Point nettoyé (espaces retirés, accessibilité sans doublon, créneaux triés) ou `.invalidInput`.
    static func validatedPoint(_ point: PickupPoint) throws -> PickupPoint {
        var point = point
        point.name = point.name.trimmingCharacters(in: .whitespacesAndNewlines)
        point.address = point.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !point.name.isEmpty else { throw AppError.invalidInput("Donne un nom à ton point de cueillette.") }
        guard point.name.count <= nameLimit else {
            throw AppError.invalidInput("Le nom fait au plus \(nameLimit) caractères.")
        }
        guard !point.address.isEmpty else { throw AppError.invalidInput("Indique l'adresse où les voisins viendront.") }
        guard point.address.count <= addressLimit else {
            throw AppError.invalidInput("L'adresse fait au plus \(addressLimit) caractères.")
        }
        guard (1...maxPointCapacity).contains(point.capacity) else {
            throw AppError.invalidInput("La capacité va de 1 à \(maxPointCapacity) parts.")
        }
        point.accessibility = PickupPoint.Accessibility.allCases.filter(point.accessibility.contains)
        point.slots = try validatedSlots(point.slots)
        return point
    }

    // MARK: Créneaux (RQ-063)

    /// Créneaux triés par début, ou `.invalidInput` : fin après début, capacité ≥ 1, pas de chevauchement.
    static func validatedSlots(_ slots: [PickupSlot]) throws -> [PickupSlot] {
        guard slots.count <= maxSlots else { throw AppError.invalidInput("Au plus \(maxSlots) créneaux.") }
        let sorted = slots.sorted { $0.start < $1.start }
        for slot in sorted {
            guard slot.end > slot.start else {
                throw AppError.invalidInput("Un créneau doit finir après son début.")
            }
            if let capacity = slot.capacity, !(1...maxSlotCapacity).contains(capacity) {
                throw AppError.invalidInput("Un créneau accueille de 1 à \(maxSlotCapacity) ménages.")
            }
        }
        for (previous, next) in zip(sorted, sorted.dropFirst()) where next.start < previous.end {
            throw AppError.invalidInput("Deux créneaux se chevauchent : décale-en un.")
        }
        return sorted
    }

    /// Créneaux de `duration` qui se suivent à partir de `start` (proposition rapide pour le coordonnateur).
    static func consecutiveSlots(from start: Date, count: Int, duration: TimeInterval, capacity: Int?) -> [PickupSlot] {
        (0..<max(0, count)).map { index in
            let begin = start.addingTimeInterval(Double(index) * duration)
            return PickupSlot(start: begin, end: begin.addingTimeInterval(duration), capacity: capacity)
        }
    }

    /// Parts dont le créneau réservé n'existe plus : la réservation est effacée.
    static func clearingRemovedSlots(_ shares: [Share], keeping slots: [PickupSlot]) -> [Share] {
        let starts = Set(slots.map(\.start))
        return shares.map { share in
            var share = share
            if let start = share.pickupSlotStart, !starts.contains(start) { share.pickupSlotStart = nil }
            return share
        }
    }

    // MARK: Réservation (RQ-064)

    /// Disponibilité de chaque créneau, triée par début.
    static func availability(of slots: [PickupSlot], shares: [Share]) -> [Availability] {
        let counts = Dictionary(grouping: shares.compactMap(\.pickupSlotStart), by: { $0 }).mapValues(\.count)
        return slots.sorted { $0.start < $1.start }.map { Availability(slot: $0, reserved: counts[$0.start, default: 0]) }
    }

    /// La part du ménage avec son nouveau créneau (`nil` = annuler), ou une erreur :
    /// `.notFound` sans part, `.invalidInput` si le créneau est inconnu ou complet.
    static func reserving(
        _ start: Date?, householdId: String, slots: [PickupSlot], shares: [Share], now: Date = .now
    ) throws -> Share {
        guard var share = shares.first(where: { $0.householdId == householdId }) else {
            throw AppError.notFound
        }
        guard let start else {
            share.pickupSlotStart = nil
            return share
        }
        guard share.pickupSlotStart != start else { return share }
        guard let slot = slots.first(where: { $0.start == start }) else {
            throw AppError.invalidInput("Ce créneau n'existe plus. Choisis-en un autre.")
        }
        guard slot.end > now else { throw AppError.invalidInput("Ce créneau est déjà passé.") }
        let others = shares.filter { $0.householdId != householdId }
        let reserved = others.filter { $0.pickupSlotStart == start }.count
        if let capacity = slot.capacity, reserved >= capacity {
            throw AppError.invalidInput("Ce créneau est complet. Choisis-en un autre.")
        }
        share.pickupSlotStart = start
        return share
    }
}
