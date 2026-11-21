import Foundation
import Testing
@testable import AMC_MobileApp

/// Règles des points et créneaux de cueillette (T-077, RQ-062 à RQ-064).
struct PickupSlotBookTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func slot(_ hour: Double, minutes: Double = 60, capacity: Int? = nil) -> PickupSlot {
        let start = Self.base.addingTimeInterval(hour * 3_600)
        return PickupSlot(start: start, end: start.addingTimeInterval(minutes * 60), capacity: capacity)
    }

    private func share(_ id: String, slot: PickupSlot? = nil) -> Share {
        Share(householdId: id, quantity: 1, finalPriceCents: nil, isPaid: false, suspendedAmountCents: 0,
              subsidyCents: 0, qrCode: nil, isPickedUp: false, pickupSlotStart: slot?.start)
    }

    private func point(name: String = "Chez Amina", address: String = "Rue Jarry", capacity: Int = 20,
                       accessibility: [PickupPoint.Accessibility] = []) -> PickupPoint {
        PickupPoint(id: "p", hostUserId: "u", name: name, address: address, photoURL: nil, capacity: capacity,
                    accessibility: accessibility, slots: [])
    }

    // MARK: Point (RQ-062)

    @Test func validPointIsTrimmedAndAccessibilityDeduplicated() throws {
        let cleaned = try PickupSlotBook.validatedPoint(point(
            name: "  Chez Amina ", address: " Rue Jarry\n", accessibility: [.parking, .stepFree, .parking]
        ))
        #expect(cleaned.name == "Chez Amina")
        #expect(cleaned.address == "Rue Jarry")
        #expect(cleaned.accessibility == [.stepFree, .parking])
    }

    @Test(arguments: [("", "Rue Jarry", 20), ("Chez moi", "  ", 20), ("Chez moi", "Rue", 0), ("Chez moi", "Rue", 1_001)])
    func invalidPointIsRefused(name: String, address: String, capacity: Int) {
        #expect(throws: AppError.self) {
            try PickupSlotBook.validatedPoint(point(name: name, address: address, capacity: capacity))
        }
    }

    // MARK: Créneaux (RQ-063)

    @Test func slotsAreSortedAndChecked() throws {
        let sorted = try PickupSlotBook.validatedSlots([slot(2), slot(0), slot(1)])
        #expect(sorted.map(\.start) == [slot(0), slot(1), slot(2)].map(\.start))
    }

    @Test func overlappingSlotsAreRefused() {
        #expect(throws: AppError.self) { try PickupSlotBook.validatedSlots([slot(0, minutes: 90), slot(1)]) }
    }

    @Test func emptyOrInvertedSlotIsRefused() {
        let start = Self.base
        #expect(throws: AppError.self) {
            try PickupSlotBook.validatedSlots([PickupSlot(start: start, end: start)])
        }
        #expect(throws: AppError.self) { try PickupSlotBook.validatedSlots([slot(0, capacity: 0)]) }
    }

    @Test func consecutiveSlotsFollowEachOther() throws {
        let slots = PickupSlotBook.consecutiveSlots(from: Self.base, count: 3, duration: 1_800, capacity: 4)
        #expect(slots.count == 3)
        #expect(slots[1].start == slots[0].end)
        #expect(slots.allSatisfy { $0.capacity == 4 })
        #expect(try PickupSlotBook.validatedSlots(slots) == slots)
    }

    @Test func removedSlotClearsReservations() {
        let kept = slot(0), removed = slot(1)
        let shares = PickupSlotBook.clearingRemovedSlots([share("a", slot: kept), share("b", slot: removed), share("c")],
                                                         keeping: [kept])
        #expect(shares.map(\.pickupSlotStart) == [kept.start, nil, nil])
    }

    // MARK: Réservation (RQ-064)

    @Test func availabilityCountsReservations() {
        let morning = slot(0, capacity: 2), noon = slot(2)
        let availability = PickupSlotBook.availability(
            of: [noon, morning], shares: [share("a", slot: morning), share("b", slot: morning), share("c", slot: noon)]
        )
        #expect(availability.map(\.slot) == [morning, noon])
        #expect(availability[0].remaining == 0)
        #expect(availability[0].isFull)
        #expect(availability[0].fillRatio == 1)
        #expect(availability[1].remaining == nil)
        #expect(!availability[1].isFull)
    }

    @Test func householdReservesFreeSlot() throws {
        let morning = slot(0, capacity: 2)
        let updated = try PickupSlotBook.reserving(
            morning.start, householdId: "a", slots: [morning], shares: [share("a"), share("b", slot: morning)],
            now: Self.base.addingTimeInterval(-60)
        )
        #expect(updated.pickupSlotStart == morning.start)
    }

    @Test func fullSlotIsRefusedButOwnSlotStays() throws {
        let morning = slot(0, capacity: 1)
        let shares = [share("a", slot: morning), share("b")]
        #expect(throws: AppError.self) {
            try PickupSlotBook.reserving(morning.start, householdId: "b", slots: [morning], shares: shares,
                                         now: Self.base.addingTimeInterval(-60))
        }
        let same = try PickupSlotBook.reserving(morning.start, householdId: "a", slots: [morning], shares: shares,
                                                now: Self.base.addingTimeInterval(-60))
        #expect(same.pickupSlotStart == morning.start)
    }

    @Test func pastOrUnknownSlotIsRefused() {
        let morning = slot(0)
        #expect(throws: AppError.self) {
            try PickupSlotBook.reserving(morning.start, householdId: "a", slots: [morning], shares: [share("a")],
                                         now: morning.end)
        }
        #expect(throws: AppError.self) {
            try PickupSlotBook.reserving(slot(5).start, householdId: "a", slots: [morning], shares: [share("a")],
                                         now: Self.base.addingTimeInterval(-60))
        }
    }

    @Test func noShareMeansNotFound() {
        #expect(throws: AppError.notFound) {
            try PickupSlotBook.reserving(nil, householdId: "z", slots: [], shares: [share("a")])
        }
    }

    @Test func nilCancelsReservation() throws {
        let morning = slot(0)
        let cancelled = try PickupSlotBook.reserving(nil, householdId: "a", slots: [morning],
                                                     shares: [share("a", slot: morning)])
        #expect(cancelled.pickupSlotStart == nil)
    }

    @Test func shareDecodesWithoutReservedSlot() throws {
        let json = #"{"householdId":"a","quantity":1,"isPaid":false,"suspendedAmountCents":0,"subsidyCents":0,"isPickedUp":false}"#
        let decoded = try JSONDecoder().decode(Share.self, from: Data(json.utf8))
        #expect(decoded.pickupSlotStart == nil)
        let slotJSON = #"{"start":0,"end":3600}"#
        #expect(try JSONDecoder().decode(PickupSlot.self, from: Data(slotJSON.utf8)).capacity == nil)
    }
}
