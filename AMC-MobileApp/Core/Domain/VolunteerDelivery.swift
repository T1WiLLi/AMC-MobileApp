// VolunteerDelivery.swift
// RQ-069 (T-117) : livraison à domicile d'une part par un voisin bénévole, pour les aînés et les
// personnes à mobilité réduite. Swift pur, partagé par le service fake et les ViewModels.
//
// Parcours : le ménage demande (`request`) → un voisin du groupe prend en charge (`claim`) → il
// récupère la part chez l'hôte et part (`startRoute`, via `PickupDesk.scan`) → il livre (`deliver`)
// → le ménage confirme la réception (`confirmReceipt`). Annulation possible tant que la part n'est pas partie.
//
// Confidentialité : `Request` (donnée partagée avec le groupe) ne contient JAMAIS d'adresse exacte,
// seulement un geohash tronqué (`publicGeohashLength` caractères, ~1 km). L'adresse vit à part
// (`PrivateAddress`) et `revealedAddress(...)` ne la montre qu'au ménage lui-même et au bénévole
// qui a pris la livraison en charge, jusqu'à la livraison.

import Foundation

nonisolated enum VolunteerDelivery {
    // MARK: - Modèle

    enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case requested
        case claimed
        case onTheWay
        case delivered
        case cancelled

        var title: String {
            switch self {
            case .requested: String(localized: "Demandée")
            case .claimed: String(localized: "Prise en charge")
            case .onTheWay: String(localized: "En route")
            case .delivered: String(localized: "Livrée")
            case .cancelled: String(localized: "Annulée")
            }
        }

        var systemImage: String {
            switch self {
            case .requested: "hand.raised.fill"
            case .claimed: "person.badge.shield.checkmark.fill"
            case .onTheWay: "figure.walk.motion"
            case .delivered: "house.fill"
            case .cancelled: "xmark.circle.fill"
            }
        }

        /// Livraison en cours chez un bénévole (compte dans sa limite).
        var isActive: Bool { self == .claimed || self == .onTheWay }
        var isFinished: Bool { self == .delivered || self == .cancelled }
    }

    /// Pourquoi le ménage a droit à la livraison.
    enum Reason: String, Codable, Sendable, CaseIterable, Hashable {
        /// Mode aîné activé dans le profil (`AppUser.seniorMode`).
        case senior
        /// Option accessibilité : mobilité réduite déclarée par le ménage.
        case reducedMobility

        var title: String {
            switch self {
            case .senior: String(localized: "Aîné")
            case .reducedMobility: String(localized: "Mobilité réduite")
            }
        }

        var systemImage: String {
            switch self {
            case .senior: "figure.walk.motion"
            case .reducedMobility: "figure.roll"
            }
        }
    }

    /// Créneau de livraison souhaité par le ménage.
    struct Window: Codable, Sendable, Hashable {
        var start: Date
        var end: Date

        func overlaps(_ other: Window) -> Bool { start < other.end && other.start < end }
    }

    /// Demande partagée avec le groupe. Aucune adresse exacte ici.
    struct Request: Identifiable, Codable, Sendable, Hashable {
        var id: String
        var groupId: String
        var groupOrderId: String
        var householdId: String
        /// Nom court affiché aux bénévoles (« Mme Tremblay »), jamais l'adresse.
        var householdName: String
        /// Quartier approximatif : geohash tronqué à `publicGeohashLength` caractères.
        var geohash: String
        var quantity: Int
        var window: Window
        var reason: Reason
        var note: String?
        var status: Status
        var volunteerHouseholdId: String?
        var volunteerName: String?
        var createdAt: Date
        var claimedAt: Date?
        var departedAt: Date?
        var deliveredAt: Date?
        var cancelledAt: Date?
        /// Le ménage a confirmé avoir reçu sa part.
        var receiptConfirmedAt: Date?
    }

    /// Adresse exacte, stockée à part et jamais copiée dans `Request`.
    struct PrivateAddress: Codable, Sendable, Hashable {
        var requestId: String
        var address: String
        /// Indications pour le bénévole (« sonnette 3, 2e étage »).
        var instructions: String?
    }

    // MARK: - Limites

    /// Livraisons en cours (prises en charge ou en route) par bénévole.
    static let maxActivePerVolunteer = 3
    /// Créneau : au moins 30 min, au plus 4 h, au plus 14 jours à l'avance.
    static let minWindow: TimeInterval = 30 * 60
    static let maxWindow: TimeInterval = 4 * 3_600
    static let maxAdvance: TimeInterval = 14 * 86_400
    static let publicGeohashLength = 6
    static let addressLimit = 200
    static let noteLimit = 140

    // MARK: - Éligibilité

    /// Le ménage a droit à la livraison s'il est en mode aîné ou a déclaré une mobilité réduite.
    /// Renvoie le motif retenu (mode aîné d'abord), ou nil.
    static func eligibility(seniorMode: Bool, reducedMobility: Bool) -> Reason? {
        if seniorMode { return .senior }
        if reducedMobility { return .reducedMobility }
        return nil
    }

    /// Geohash public : tronqué pour ne jamais situer une porte précise.
    static func publicGeohash(_ geohash: String) -> String {
        String(geohash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(publicGeohashLength))
    }

    // MARK: - Créneau

    static func validatedWindow(_ window: Window, now: Date) throws -> Window {
        guard window.end > window.start else {
            throw AppError.invalidInput(String(localized: "Le créneau doit finir après son début."))
        }
        let length = window.end.timeIntervalSince(window.start)
        guard length >= minWindow else {
            throw AppError.invalidInput(String(localized: "Laisse au moins 30 minutes au bénévole."))
        }
        guard length <= maxWindow else {
            throw AppError.invalidInput(String(localized: "Le créneau dure au plus 4 heures."))
        }
        guard window.end > now else {
            throw AppError.invalidInput(String(localized: "Ce créneau est déjà passé : choisis-en un autre."))
        }
        guard window.start <= now.addingTimeInterval(maxAdvance) else {
            throw AppError.invalidInput(String(localized: "Choisis un créneau dans les 14 prochains jours."))
        }
        return window
    }

    // MARK: - Demande

    struct NewRequest: Sendable, Hashable {
        var id: String
        var groupId: String
        var order: GroupOrder
        var share: Share?
        var householdName: String
        var householdGeohash: String
        var window: Window
        var seniorMode: Bool
        var reducedMobility: Bool
        var address: String
        var instructions: String?
        var note: String?
    }

    /// Valide une demande et sépare la partie partagée de l'adresse privée.
    /// - Parameter existing: demandes déjà connues (pour refuser un doublon actif sur la même commande).
    static func request(
        _ input: NewRequest, existing: [Request], now: Date
    ) throws -> (request: Request, address: PrivateAddress) {
        guard let reason = eligibility(seniorMode: input.seniorMode, reducedMobility: input.reducedMobility) else {
            throw AppError.invalidInput(String(localized: "La livraison est réservée au mode aîné et aux personnes à mobilité réduite."))
        }
        guard input.order.status != .cancelled else { throw AppError.orderClosed }
        guard let share = input.share, share.quantity > 0 else {
            throw AppError.invalidInput(String(localized: "Réserve d'abord ta part dans ce lot."))
        }
        guard !share.isPickedUp else {
            throw AppError.invalidInput(String(localized: "Ta part a déjà été récupérée."))
        }
        let householdId = share.householdId
        if existing.contains(where: {
            $0.householdId == householdId && $0.groupOrderId == input.order.id && !$0.status.isFinished
        }) {
            throw AppError.invalidInput(String(localized: "Tu as déjà une demande de livraison pour cette commande."))
        }
        let window = try validatedWindow(input.window, now: now)
        let address = input.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            throw AppError.invalidInput(String(localized: "Indique ton adresse : seul ton bénévole la verra."))
        }
        guard address.count <= addressLimit else {
            throw AppError.invalidInput(String(localized: "L'adresse fait au plus \(addressLimit) caractères."))
        }
        let note = trimmed(input.note)
        if let note, note.count > noteLimit {
            throw AppError.invalidInput(String(localized: "Le mot au bénévole fait au plus \(noteLimit) caractères."))
        }
        let request = Request(
            id: input.id, groupId: input.groupId, groupOrderId: input.order.id, householdId: householdId,
            householdName: input.householdName, geohash: publicGeohash(input.householdGeohash),
            quantity: share.quantity, window: window, reason: reason, note: note, status: .requested,
            volunteerHouseholdId: nil, volunteerName: nil, createdAt: now
        )
        let privateAddress = PrivateAddress(
            requestId: input.id, address: address,
            instructions: trimmed(input.instructions).map { String($0.prefix(addressLimit)) }
        )
        return (request, privateAddress)
    }

    // MARK: - Bénévole

    /// Livraisons en cours d'un bénévole.
    static func activeCount(of volunteerHouseholdId: String, in requests: [Request]) -> Int {
        requests.filter { $0.volunteerHouseholdId == volunteerHouseholdId && $0.status.isActive }.count
    }

    /// Le bénévole peut-il encore prendre une livraison ?
    static func canTakeMore(_ volunteerHouseholdId: String, in requests: [Request]) -> Bool {
        activeCount(of: volunteerHouseholdId, in: requests) < maxActivePerVolunteer
    }

    /// Prise en charge par un voisin du même groupe.
    /// - Parameter all: toutes les demandes du groupe (limite et chevauchement des créneaux).
    static func claim(
        _ request: Request, volunteerHouseholdId: String, volunteerName: String,
        volunteerGroupIds: Set<String>, all: [Request], now: Date
    ) throws -> Request {
        guard request.status == .requested else {
            throw AppError.invalidInput(String(localized: "Un autre voisin a déjà pris cette livraison."))
        }
        guard volunteerHouseholdId != request.householdId else {
            throw AppError.invalidInput(String(localized: "Tu ne peux pas livrer ta propre part."))
        }
        guard volunteerGroupIds.contains(request.groupId) else { throw AppError.permissionDenied }
        guard request.window.end > now else {
            throw AppError.invalidInput(String(localized: "Le créneau de cette livraison est passé."))
        }
        let mine = all.filter { $0.volunteerHouseholdId == volunteerHouseholdId && $0.status.isActive }
        guard mine.count < maxActivePerVolunteer else {
            throw AppError.invalidInput(String(localized: "Tu as déjà \(maxActivePerVolunteer) livraisons en cours : termine-en une avant d'en prendre une autre."))
        }
        guard !mine.contains(where: { $0.window.overlaps(request.window) }) else {
            throw AppError.invalidInput(String(localized: "Ce créneau chevauche une autre de tes livraisons."))
        }
        var claimed = request
        claimed.status = .claimed
        claimed.volunteerHouseholdId = volunteerHouseholdId
        claimed.volunteerName = volunteerName
        claimed.claimedAt = now
        return claimed
    }

    /// Le bénévole se désiste : la demande redevient visible pour les autres voisins.
    static func release(_ request: Request, by volunteerHouseholdId: String) throws -> Request {
        guard request.volunteerHouseholdId == volunteerHouseholdId else { throw AppError.permissionDenied }
        guard request.status == .claimed else {
            throw AppError.invalidInput(String(localized: "Tu as déjà récupéré la part : livre-la ou contacte l'hôte."))
        }
        var released = request
        released.status = .requested
        released.volunteerHouseholdId = nil
        released.volunteerName = nil
        released.claimedAt = nil
        return released
    }

    /// Le bénévole récupère la part chez l'hôte (même règle que la cueillette, `PickupDesk.scan`) et part.
    /// Renvoie la demande « en route » et la part marquée comme cueillie, à enregistrer.
    static func startRoute(
        _ request: Request, by volunteerHouseholdId: String, order: GroupOrder, shares: [Share], now: Date
    ) throws -> (request: Request, share: Share) {
        guard request.volunteerHouseholdId == volunteerHouseholdId else { throw AppError.permissionDenied }
        guard request.status == .claimed else {
            throw AppError.invalidInput(String(localized: "Cette livraison n'est pas prête à partir."))
        }
        // Sécurité : le bénévole n'a pas le code de la famille (jeton privé) ; même règle de remise que l'hôte.
        let result = PickupDesk.handOver(householdId: request.householdId, order: order, shares: shares,
                                         pickedUpBy: nil, at: now)
        guard case .pickedUp(let share) = result else {
            throw AppError.invalidInput(result.message)
        }
        var started = request
        started.status = .onTheWay
        started.departedAt = now
        return (started, share)
    }

    /// Le bénévole a remis la part au ménage.
    static func deliver(_ request: Request, by volunteerHouseholdId: String, now: Date) throws -> Request {
        guard request.volunteerHouseholdId == volunteerHouseholdId else { throw AppError.permissionDenied }
        guard request.status == .onTheWay else {
            throw AppError.invalidInput(String(localized: "Récupère d'abord la part chez l'hôte."))
        }
        var delivered = request
        delivered.status = .delivered
        delivered.deliveredAt = now
        return delivered
    }

    // MARK: - Ménage

    /// Le ménage confirme avoir reçu sa part.
    static func confirmReceipt(_ request: Request, by householdId: String, now: Date) throws -> Request {
        guard request.householdId == householdId else { throw AppError.permissionDenied }
        guard request.status == .delivered else {
            throw AppError.invalidInput(String(localized: "Ta part n'est pas encore arrivée."))
        }
        guard request.receiptConfirmedAt == nil else { return request }
        var confirmed = request
        confirmed.receiptConfirmedAt = now
        return confirmed
    }

    /// Le ménage annule tant que la part n'a pas quitté l'hôte.
    static func cancel(_ request: Request, by householdId: String, now: Date) throws -> Request {
        guard request.householdId == householdId else { throw AppError.permissionDenied }
        guard request.status == .requested || request.status == .claimed else {
            throw AppError.invalidInput(
                request.status == .onTheWay
                    ? String(localized: "Ton bénévole est déjà en route : il arrive bientôt.")
                    : String(localized: "Cette livraison est terminée.")
            )
        }
        var cancelled = request
        cancelled.status = .cancelled
        cancelled.cancelledAt = now
        return cancelled
    }

    // MARK: - Confidentialité

    /// Peut voir l'adresse exacte : le ménage lui-même, ou le bénévole tant qu'il livre.
    static func canSeeAddress(_ request: Request, viewerHouseholdId: String) -> Bool {
        if viewerHouseholdId == request.householdId { return !request.status.isFinished }
        return request.volunteerHouseholdId == viewerHouseholdId && request.status.isActive
    }

    static func revealedAddress(
        for request: Request, viewerHouseholdId: String, addresses: [PrivateAddress]
    ) -> PrivateAddress? {
        guard canSeeAddress(request, viewerHouseholdId: viewerHouseholdId) else { return nil }
        return addresses.first { $0.requestId == request.id }
    }

    // MARK: - Listes

    /// Demandes à prendre pour un bénévole : du groupe, pas les siennes, créneau pas encore fini, plus tôt d'abord.
    static func openRequests(groupId: String, for volunteerHouseholdId: String, in requests: [Request],
                             now: Date) -> [Request] {
        requests
            .filter {
                $0.groupId == groupId && $0.status == .requested
                    && $0.householdId != volunteerHouseholdId && $0.window.end > now
            }
            .sorted { ($0.window.start, $0.id) < ($1.window.start, $1.id) }
    }

    /// Livraisons d'un bénévole : en cours d'abord (plus tôt d'abord), puis terminées (plus récentes d'abord).
    static func deliveries(of volunteerHouseholdId: String, in requests: [Request]) -> [Request] {
        let mine = requests.filter { $0.volunteerHouseholdId == volunteerHouseholdId && $0.status != .cancelled }
        let active = mine.filter(\.status.isActive).sorted { $0.window.start < $1.window.start }
        let done = mine.filter { !$0.status.isActive }.sorted { $0.window.start > $1.window.start }
        return active + done
    }

    // MARK: - Suivi

    struct Step: Identifiable, Sendable, Hashable {
        var status: Status
        var date: Date?
        var isDone: Bool
        var isCurrent: Bool

        var id: Status { status }
    }

    /// Étapes du suivi : demandée → prise en charge → en route → livrée.
    static func steps(of request: Request) -> [Step] {
        let order: [Status] = [.requested, .claimed, .onTheWay, .delivered]
        let dates: [Status: Date?] = [
            .requested: request.createdAt, .claimed: request.claimedAt,
            .onTheWay: request.departedAt, .delivered: request.deliveredAt,
        ]
        let reached = order.firstIndex(of: request.status) ?? -1
        return order.enumerated().map { index, status in
            Step(status: status, date: dates[status] ?? nil, isDone: index <= reached,
                 isCurrent: index == reached && request.status != .delivered)
        }
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
