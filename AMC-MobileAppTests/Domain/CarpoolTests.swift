import Foundation
import Testing
@testable import AMC_MobileApp

/// RQ-070 (T-118) : offre de trajet, réservation, complet, annulation, rappels, point approximatif.
struct CarpoolTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let slot = PickupSlot(start: now.addingTimeInterval(2 * 3_600), end: now.addingTimeInterval(5 * 3_600))

    static func ride(seats: Int = 2, cargo: Int = 4, bookings: [Carpool.Booking] = [],
                     departure: Date? = nil, geohash: String = "f25dvs2k") -> Carpool.Ride {
        Carpool.Ride(
            id: "ride-1", groupId: "g1", pickupPointId: "p1", slot: slot, driverHouseholdId: "driver",
            driverFirstName: "  Karim ", departure: departure ?? now.addingTimeInterval(90 * 60),
            meetingGeohash: geohash, seats: seats, cargoShares: cargo, note: " Coffre propre ", bookings: bookings
        )
    }

    static func request(_ household: String = "h2", seats: Int = 0, cargo: Int = 0) -> Carpool.Booking {
        Carpool.Booking(householdId: household, householdName: "Famille \(household)", seats: seats, cargoShares: cargo)
    }

    static func message(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let AppError.invalidInput(message) { return message } catch { return "\(error)" }
    }

    // MARK: Point de rencontre

    @Test func meetingPointIsTruncatedNeverExact() throws {
        #expect(try Carpool.approximateMeetingPoint(" F25DVS2K9 ") == "f25dvs")
        #expect(try Carpool.approximateMeetingPoint("f25dv") == "f25dv")
    }

    @Test func meetingPointRejectsVagueOrInvalidHashes() {
        #expect(Self.message { _ = try Carpool.approximateMeetingPoint("f25d") } != nil)
        #expect(Self.message { _ = try Carpool.approximateMeetingPoint("f25a!") } != nil)
        #expect(Self.message { _ = try Carpool.approximateMeetingPoint("") } != nil)
    }

    // MARK: Offre

    @Test func validOfferIsCleaned() throws {
        let ride = try Carpool.validatedOffer(Self.ride(), now: Self.now)
        #expect(ride.driverFirstName == "Karim")
        #expect(ride.note == "Coffre propre")
        #expect(ride.meetingGeohash == "f25dvs")
        #expect(ride.remainingSeats == 2)
        #expect(ride.remainingCargoShares == 4)
    }

    @Test func offerNeedsSeatsOrCargo() {
        #expect(Self.message { _ = try Carpool.validatedOffer(Self.ride(seats: 0, cargo: 0), now: Self.now) } != nil)
        #expect(Self.message { _ = try Carpool.validatedOffer(Self.ride(seats: 0, cargo: 3), now: Self.now) } == nil)
        #expect(Self.message { _ = try Carpool.validatedOffer(Self.ride(seats: 7), now: Self.now) } != nil)
        #expect(Self.message { _ = try Carpool.validatedOffer(Self.ride(cargo: 31), now: Self.now) } != nil)
    }

    @Test func offerDepartureMustFitTheSlot() {
        let past = Self.ride(departure: Self.now.addingTimeInterval(-60))
        let afterSlot = Self.ride(departure: Self.slot.end)
        let tooEarly = Self.ride(departure: Self.slot.start.addingTimeInterval(-3 * 3_600 - 60))
        #expect(Self.message { _ = try Carpool.validatedOffer(past, now: Self.now) } != nil)
        #expect(Self.message { _ = try Carpool.validatedOffer(afterSlot, now: Self.now) } != nil)
        #expect(Self.message { _ = try Carpool.validatedOffer(tooEarly, now: Self.now) } != nil)
    }

    @Test func editedOfferCannotDropBelowBookings() {
        let booked = Self.ride(seats: 2, bookings: [Self.request(seats: 2)])
        var shrunk = booked
        shrunk.seats = 1
        #expect(Self.message { _ = try Carpool.validatedOffer(shrunk, now: Self.now) } != nil)
    }

    // MARK: Réservation

    @Test func bookingSeatsAndCargo() throws {
        let ride = try Carpool.booking(Self.request(seats: 1, cargo: 2), on: Self.ride(), now: Self.now)
        #expect(ride.remainingSeats == 1)
        #expect(ride.remainingCargoShares == 2)
        #expect(ride.booking(of: "h2")?.bookedAt == Self.now)
    }

    @Test func rebookingReplacesTheHouseholdsBooking() throws {
        var ride = try Carpool.booking(Self.request(seats: 2), on: Self.ride(), now: Self.now)
        #expect(ride.remainingSeats == 0)
        ride = try Carpool.booking(Self.request(seats: 1, cargo: 1), on: ride, now: Self.now)
        #expect(ride.bookings.count == 1)
        #expect(ride.remainingSeats == 1)
        #expect(ride.remainingCargoShares == 3)
    }

    @Test func bookingIsRefusedWhenFull() throws {
        let full = try Carpool.booking(Self.request("h2", seats: 2, cargo: 4), on: Self.ride(), now: Self.now)
        #expect(full.isFull)
        #expect(Self.message { _ = try Carpool.booking(Self.request("h3", seats: 1), on: full, now: Self.now) }
            == "Plus de place dans la voiture.")
        #expect(Self.message { _ = try Carpool.booking(Self.request("h3", cargo: 1), on: full, now: Self.now) }
            == "Le coffre est plein.")
    }

    @Test func bookingBeyondWhatRemainsSaysHowMuchIsLeft() throws {
        let ride = try Carpool.booking(Self.request("h2", seats: 1, cargo: 3), on: Self.ride(), now: Self.now)
        #expect(Self.message { _ = try Carpool.booking(Self.request("h3", seats: 2), on: ride, now: Self.now) }
            == "Il reste 1 place.")
        #expect(Self.message { _ = try Carpool.booking(Self.request("h3", cargo: 2), on: ride, now: Self.now) }
            == "Le coffre peut encore prendre 1 part.")
    }

    @Test func bookingIsRefusedForDriverEmptyCancelledOrDeparted() {
        var cancelled = Self.ride()
        cancelled.isCancelled = true
        #expect(Self.message { _ = try Carpool.booking(Self.request("driver", seats: 1), on: Self.ride(), now: Self.now) } != nil)
        #expect(Self.message { _ = try Carpool.booking(Self.request(), on: Self.ride(), now: Self.now) } != nil)
        #expect(Self.message { _ = try Carpool.booking(Self.request(seats: 1), on: cancelled, now: Self.now) } != nil)
        let later = Self.now.addingTimeInterval(2 * 3_600)
        #expect(Self.message { _ = try Carpool.booking(Self.request(seats: 1), on: Self.ride(), now: later) } != nil)
    }

    // MARK: Annulation

    @Test func cancellingABookingFreesItsSpace() throws {
        let ride = try Carpool.booking(Self.request(seats: 2), on: Self.ride(), now: Self.now)
        let freed = Carpool.cancellingBooking(of: "h2", on: ride)
        #expect(freed.bookings.isEmpty)
        #expect(freed.remainingSeats == 2)
    }

    @Test func onlyTheDriverCancelsTheRideAndBookersAreNotified() throws {
        var ride = try Carpool.booking(Self.request("h2", seats: 1), on: Self.ride(), now: Self.now)
        ride = try Carpool.booking(Self.request("h3", cargo: 2), on: ride, now: Self.now)
        #expect(throws: AppError.permissionDenied) { _ = try Carpool.cancellingRide(ride, by: "h2") }
        let result = try Carpool.cancellingRide(ride, by: "driver")
        #expect(result.ride.isCancelled)
        #expect(Set(result.notices.map(\.householdId)) == ["h2", "h3"])
        #expect(try Carpool.cancellingRide(result.ride, by: "driver").notices.isEmpty)
    }

    // MARK: Rappels

    @Test func remindersForDriverAndEachBooker() throws {
        var ride = try Carpool.booking(Self.request("h2", seats: 1), on: Self.ride(), now: Self.now)
        ride = try Carpool.booking(Self.request("h3", cargo: 1), on: ride, now: Self.now)
        let reminders = Carpool.reminders(for: ride, now: Self.now)
        #expect(reminders.count == 3)
        #expect(reminders.first?.role == .driver)
        #expect(reminders.first?.body == "2 ménages comptent sur toi pour la cueillette.")
        #expect(reminders.allSatisfy { $0.fireDate == ride.departure.addingTimeInterval(-30 * 60) })
    }

    @Test func noRemindersWhenCancelledEmptyOrTooLate() throws {
        #expect(Carpool.reminders(for: Self.ride(), now: Self.now).isEmpty)
        let ride = try Carpool.booking(Self.request(seats: 1), on: Self.ride(), now: Self.now)
        let late = ride.departure.addingTimeInterval(-10 * 60)
        #expect(Carpool.reminders(for: ride, now: late).isEmpty)
        let cancelled = try Carpool.cancellingRide(ride, by: "driver").ride
        #expect(Carpool.reminders(for: cancelled, now: Self.now).isEmpty)
    }

    @Test func upcomingSkipsCancelledAndDeparted() {
        var cancelled = Self.ride()
        cancelled.id = "ride-2"
        cancelled.isCancelled = true
        var gone = Self.ride(departure: Self.now.addingTimeInterval(-60))
        gone.id = "ride-3"
        var later = Self.ride(departure: Self.now.addingTimeInterval(2 * 3_600))
        later.id = "ride-4"
        #expect(Carpool.upcoming([later, cancelled, gone, Self.ride()], now: Self.now).map(\.id) == ["ride-1", "ride-4"])
    }
}
