// Carpool.swift
// RQ-070 (T-118) : covoiturage vers le point de cueillette, en Swift pur (fakes, ViewModels, tests).
//   - un membre qui y va en voiture propose un trajet pour un créneau : places passagers et volume de coffre en parts ;
//   - un autre ménage réserve des places et/ou fait transporter ses parts ; refus quand c'est complet ;
//   - annulation (réservation ou trajet entier) et rappels avant le départ.
// Le point de rencontre est un geohash approximatif (au plus `meetingPrecision` caractères), jamais une adresse.
//
// Usage :
//   let ride = try Carpool.validatedOffer(draft, now: .now)
//   let booked = try Carpool.booking(.init(householdId: "h2", householdName: "Famille Tremblay", seats: 1, cargoShares: 2), on: ride)
//   Carpool.reminders(for: booked)   // un rappel pour le conducteur et un pour chaque ménage, 30 min avant le départ

import Foundation

nonisolated enum Carpool {
    /// Un trajet proposé vers un point de cueillette, pour un créneau.
    struct Ride: Identifiable, Codable, Sendable, Hashable {
        var id: String
        var groupId: String
        var pickupPointId: String
        var slot: PickupSlot
        var driverHouseholdId: String
        /// Prénom du conducteur (« Karim »), jamais son adresse.
        var driverFirstName: String
        /// Heure de départ du point de rencontre.
        var departure: Date
        /// Point de rencontre approximatif (geohash de `meetingPrecision` caractères au plus).
        var meetingGeohash: String
        /// Places passagers offertes (sans compter le conducteur).
        var seats: Int
        /// Parts que le coffre peut transporter pour d'autres ménages.
        var cargoShares: Int
        var note: String = ""
        var bookings: [Booking] = []
        var isCancelled = false

        var bookedSeats: Int { bookings.reduce(0) { $0 + $1.seats } }
        var bookedCargoShares: Int { bookings.reduce(0) { $0 + $1.cargoShares } }
        var remainingSeats: Int { max(0, seats - bookedSeats) }
        var remainingCargoShares: Int { max(0, cargoShares - bookedCargoShares) }
        /// Plus aucune place ni aucun espace de coffre.
        var isFull: Bool { remainingSeats == 0 && remainingCargoShares == 0 }

        func booking(of householdId: String) -> Booking? { bookings.first { $0.householdId == householdId } }
        func isDriver(_ householdId: String) -> Bool { driverHouseholdId == householdId }
    }

    /// Réservation d'un ménage sur un trajet : des places, des parts dans le coffre, ou les deux.
    struct Booking: Identifiable, Codable, Sendable, Hashable {
        var householdId: String
        var householdName: String
        var seats: Int = 0
        var cargoShares: Int = 0
        var bookedAt: Date = .now

        var id: String { householdId }
    }

    /// Rappel local à programmer (notification) avant un départ.
    struct Reminder: Sendable, Hashable, Identifiable {
        enum Role: Sendable, Hashable {
            case driver
            case passenger
        }

        var rideId: String
        var householdId: String
        var role: Role
        var fireDate: Date
        var title: String
        var body: String

        var id: String { "\(rideId)/\(householdId)" }
    }

    /// Avis d'annulation à envoyer aux ménages qui avaient réservé.
    struct CancellationNotice: Sendable, Hashable {
        var rideId: String
        var householdId: String
        var message: String
    }

    static let maxSeats = 6
    static let maxCargoShares = 30
    static let noteLimit = 140
    /// Précision max du point de rencontre : 6 caractères ≈ 1,2 km × 0,6 km.
    static let meetingPrecision = 6
    /// Précision min : en dessous de 5 (≈ 5 km), le point ne sert plus à rien.
    static let minMeetingPrecision = 5
    /// Départ au plus tôt 3 h avant le début du créneau.
    static let maxLeadBeforeSlot: TimeInterval = 3 * 3_600
    /// Rappel par défaut : 30 min avant le départ.
    static let defaultReminderLead: TimeInterval = 30 * 60

    // MARK: Point de rencontre

    /// Geohash nettoyé et tronqué à `meetingPrecision`, ou `.invalidInput` s'il est invalide ou trop vague.
    static func approximateMeetingPoint(_ geohash: String) throws -> String {
        let hash = geohash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Geohash.isValid(hash) else {
            throw AppError.invalidInput("Choisis un point de rencontre sur la carte.")
        }
        guard hash.count >= minMeetingPrecision else {
            throw AppError.invalidInput("Le point de rencontre est trop vague : rapproche-toi du quartier.")
        }
        return String(hash.prefix(meetingPrecision))
    }

    // MARK: Offre de trajet

    /// Trajet nettoyé (prénom, note, point approximatif) ou `.invalidInput` :
    /// places 0…6, coffre 0…30, au moins l'un des deux, départ à venir, avant la fin du créneau
    /// et au plus 3 h avant son début.
    static func validatedOffer(_ ride: Ride, now: Date = .now) throws -> Ride {
        var ride = ride
        ride.driverFirstName = ride.driverFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        ride.note = ride.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ride.driverFirstName.isEmpty else { throw AppError.invalidInput("Indique ton prénom.") }
        guard (0...maxSeats).contains(ride.seats) else {
            throw AppError.invalidInput("Propose de 0 à \(maxSeats) places.")
        }
        guard (0...maxCargoShares).contains(ride.cargoShares) else {
            throw AppError.invalidInput("Le coffre accueille de 0 à \(maxCargoShares) parts.")
        }
        guard ride.seats + ride.cargoShares > 0 else {
            throw AppError.invalidInput("Propose au moins une place ou de l'espace dans le coffre.")
        }
        guard ride.note.count <= noteLimit else {
            throw AppError.invalidInput("La note fait au plus \(noteLimit) caractères.")
        }
        guard ride.slot.end > now else { throw AppError.invalidInput("Ce créneau est déjà passé.") }
        guard ride.departure > now else { throw AppError.invalidInput("L'heure de départ est déjà passée.") }
        guard ride.departure < ride.slot.end else {
            throw AppError.invalidInput("Pars avant la fin du créneau de cueillette.")
        }
        guard ride.departure >= ride.slot.start.addingTimeInterval(-maxLeadBeforeSlot) else {
            throw AppError.invalidInput("Pars au plus 3 h avant le début du créneau.")
        }
        ride.meetingGeohash = try approximateMeetingPoint(ride.meetingGeohash)
        // Une offre modifiée ne peut pas descendre sous ce qui est déjà réservé.
        guard ride.seats >= ride.bookedSeats, ride.cargoShares >= ride.bookedCargoShares else {
            throw AppError.invalidInput("Des voisins ont déjà réservé : garde au moins leurs places et leurs parts.")
        }
        return ride
    }

    // MARK: Réservation

    /// Le trajet avec la réservation du ménage (une nouvelle réservation remplace l'ancienne), ou une erreur :
    /// `.invalidInput` si le trajet est annulé, parti, si c'est le conducteur, si la demande est vide ou dépasse
    /// les places ou le coffre restants (« complet »).
    static func booking(_ request: Booking, on ride: Ride, now: Date = .now) throws -> Ride {
        guard !ride.isCancelled else { throw AppError.invalidInput("Ce trajet a été annulé.") }
        guard ride.departure > now else { throw AppError.invalidInput("Ce trajet est déjà parti.") }
        guard !ride.isDriver(request.householdId) else {
            throw AppError.invalidInput("C'est ton trajet : tu ne peux pas y réserver.")
        }
        guard request.seats >= 0, request.cargoShares >= 0, request.seats + request.cargoShares > 0 else {
            throw AppError.invalidInput("Choisis au moins une place ou une part à transporter.")
        }
        var updated = ride
        updated.bookings.removeAll { $0.householdId == request.householdId }
        if request.seats > updated.remainingSeats {
            throw AppError.invalidInput(updated.remainingSeats == 0
                ? "Plus de place dans la voiture."
                : "Il reste \(FrenchPlural.count(updated.remainingSeats, "place")).")
        }
        if request.cargoShares > updated.remainingCargoShares {
            throw AppError.invalidInput(updated.remainingCargoShares == 0
                ? "Le coffre est plein."
                : "Le coffre peut encore prendre \(FrenchPlural.count(updated.remainingCargoShares, "part")).")
        }
        var request = request
        request.bookedAt = now
        updated.bookings.append(request)
        updated.bookings.sort { $0.bookedAt < $1.bookedAt }
        return updated
    }

    /// Le trajet sans la réservation du ménage (aucun effet s'il n'avait rien réservé).
    static func cancellingBooking(of householdId: String, on ride: Ride) -> Ride {
        var ride = ride
        ride.bookings.removeAll { $0.householdId == householdId }
        return ride
    }

    /// Le trajet annulé par son conducteur et les avis pour les ménages qui avaient réservé,
    /// ou `.permissionDenied` si quelqu'un d'autre essaie.
    static func cancellingRide(
        _ ride: Ride, by householdId: String
    ) throws -> (ride: Ride, notices: [CancellationNotice]) {
        guard ride.isDriver(householdId) else { throw AppError.permissionDenied }
        guard !ride.isCancelled else { return (ride, []) }
        var cancelled = ride
        cancelled.isCancelled = true
        let notices = ride.bookings.map { booking in
            CancellationNotice(
                rideId: ride.id, householdId: booking.householdId,
                message: "\(ride.driverFirstName) a annulé son trajet. Ta réservation est libérée : choisis un autre trajet."
            )
        }
        return (cancelled, notices)
    }

    // MARK: Rappels

    /// Rappels à programmer `lead` avant le départ : le conducteur (s'il a des réservations) et chaque ménage.
    /// Aucun pour un trajet annulé ; un rappel dont l'heure est passée est omis.
    static func reminders(for ride: Ride, lead: TimeInterval = defaultReminderLead, now: Date = .now) -> [Reminder] {
        guard !ride.isCancelled else { return [] }
        let fireDate = ride.departure.addingTimeInterval(-lead)
        guard fireDate > now else { return [] }
        let minutes = Int(lead / 60)
        var reminders: [Reminder] = []
        if !ride.bookings.isEmpty {
            reminders.append(Reminder(
                rideId: ride.id, householdId: ride.driverHouseholdId, role: .driver, fireDate: fireDate,
                title: "Départ dans \(minutes) min",
                body: "\(FrenchPlural.count(ride.bookings.count, "ménage")) \(FrenchPlural.word(ride.bookings.count, "compte", plural: "comptent")) sur toi pour la cueillette."
            ))
        }
        for booking in ride.bookings {
            reminders.append(Reminder(
                rideId: ride.id, householdId: booking.householdId, role: .passenger, fireDate: fireDate,
                title: "Covoiturage dans \(minutes) min",
                body: "\(ride.driverFirstName) part bientôt du point de rencontre."
            ))
        }
        return reminders
    }

    // MARK: Liste

    /// Trajets d'un créneau encore utiles (non annulés, pas partis), triés par départ.
    static func upcoming(_ rides: [Ride], now: Date = .now) -> [Ride] {
        rides.filter { !$0.isCancelled && $0.departure > now }.sorted { $0.departure < $1.departure }
    }
}
