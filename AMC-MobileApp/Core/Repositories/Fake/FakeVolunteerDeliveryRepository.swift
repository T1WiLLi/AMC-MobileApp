// FakeVolunteerDeliveryRepository.swift
// Livraisons à domicile en mémoire (RQ-069, T-117) : previews, tests et démo sans réseau.
// Mêmes règles que le dépôt Firestore (toutes portées par `VolunteerDelivery`) ; l'actor sérialise les
// appels, ce qui joue le rôle de la transaction quand deux voisins prennent la même livraison.
// Différence assumée : la part n'est pas marquée cueillie dans le dépôt fake des commandes (`startRoute`),
// faute d'API publique pour le faire ; le dépôt Firestore, lui, l'écrit dans la même transaction.

import Foundation

actor FakeVolunteerDeliveryRepository: VolunteerDeliveryRepository {
    private let behavior: FakeBehavior
    private let now: @Sendable () -> Date
    private var requests: [String: VolunteerDelivery.Request]
    private var addresses: [String: VolunteerDelivery.PrivateAddress]

    init(
        behavior: FakeBehavior = .instant,
        requests: [VolunteerDelivery.Request] = [],
        addresses: [VolunteerDelivery.PrivateAddress] = [],
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.behavior = behavior
        self.now = now
        self.requests = Dictionary(requests.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.addresses = Dictionary(addresses.map { ($0.requestId, $0) }, uniquingKeysWith: { _, last in last })
    }

    func deliveries(ofGroup groupId: String) async throws -> [VolunteerDelivery.Request] {
        try await behavior.simulate()
        return requests.values.filter { $0.groupId == groupId }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    @discardableResult
    func createDelivery(
        _ request: VolunteerDelivery.Request, address: VolunteerDelivery.PrivateAddress
    ) async throws -> VolunteerDelivery.Request {
        try await behavior.simulate()
        guard address.requestId == request.id else { throw AppError.invalidInput("Adresse d'une autre demande.") }
        guard requests[request.id] == nil else { throw AppError.invalidInput("Cette demande existe déjà.") }
        if requests.values.contains(where: {
            $0.householdId == request.householdId && $0.groupOrderId == request.groupOrderId && !$0.status.isFinished
        }) {
            throw AppError.invalidInput("Tu as déjà une demande de livraison pour cette commande.")
        }
        var created = request
        created.status = .requested
        requests[created.id] = created
        addresses[created.id] = address
        return created
    }

    @discardableResult
    func claimDelivery(
        id: String, groupOrderId: String, volunteerHouseholdId: String, volunteerName: String,
        volunteerGroupIds: Set<String>
    ) async throws -> VolunteerDelivery.Request {
        try await update(id, groupOrderId) { request, all, now in
            try VolunteerDelivery.claim(
                request, volunteerHouseholdId: volunteerHouseholdId, volunteerName: volunteerName,
                volunteerGroupIds: volunteerGroupIds, all: all, now: now
            )
        }
    }

    @discardableResult
    func releaseDelivery(id: String, groupOrderId: String, volunteerHouseholdId: String) async throws
        -> VolunteerDelivery.Request {
        try await update(id, groupOrderId) { request, _, _ in
            try VolunteerDelivery.release(request, by: volunteerHouseholdId)
        }
    }

    @discardableResult
    func startRoute(id: String, groupOrderId: String, volunteerHouseholdId: String) async throws
        -> VolunteerDelivery.Request {
        try await update(id, groupOrderId) { request, _, now in
            guard request.volunteerHouseholdId == volunteerHouseholdId else { throw AppError.permissionDenied }
            guard request.status == .claimed else {
                throw AppError.invalidInput("Cette livraison n'est pas prête à partir.")
            }
            var started = request
            started.status = .onTheWay
            started.departedAt = now
            return started
        }
    }

    @discardableResult
    func markDelivered(id: String, groupOrderId: String, volunteerHouseholdId: String) async throws
        -> VolunteerDelivery.Request {
        try await update(id, groupOrderId) { request, _, now in
            try VolunteerDelivery.deliver(request, by: volunteerHouseholdId, now: now)
        }
    }

    @discardableResult
    func confirmReceipt(id: String, groupOrderId: String, householdId: String) async throws
        -> VolunteerDelivery.Request {
        try await update(id, groupOrderId) { request, _, now in
            try VolunteerDelivery.confirmReceipt(request, by: householdId, now: now)
        }
    }

    @discardableResult
    func cancelDelivery(id: String, groupOrderId: String, householdId: String) async throws
        -> VolunteerDelivery.Request {
        try await update(id, groupOrderId) { request, _, now in
            try VolunteerDelivery.cancel(request, by: householdId, now: now)
        }
    }

    func address(ofDelivery id: String, groupOrderId: String, viewerHouseholdId: String) async throws
        -> VolunteerDelivery.PrivateAddress? {
        try await behavior.simulate()
        guard let request = requests[id], request.groupOrderId == groupOrderId else { throw AppError.notFound }
        return VolunteerDelivery.revealedAddress(
            for: request, viewerHouseholdId: viewerHouseholdId, addresses: Array(addresses.values)
        )
    }

    // MARK: - Interne

    private func update(
        _ id: String, _ groupOrderId: String,
        _ transform: (VolunteerDelivery.Request, [VolunteerDelivery.Request], Date) throws -> VolunteerDelivery.Request
    ) async throws -> VolunteerDelivery.Request {
        try await behavior.simulate()
        // Relu APRÈS la latence : un autre appel a pu passer pendant l'attente (comme une transaction).
        guard let current = requests[id], current.groupOrderId == groupOrderId else { throw AppError.notFound }
        let group = requests.values.filter { $0.groupId == current.groupId }
        let updated = try transform(current, group, now())
        requests[id] = updated
        return updated
    }
}

// MARK: - Démo

extension FakeVolunteerDeliveryRepository {
    /// Saint-Michel : trois voisins aînés attendent un bénévole, et Amina livre déjà Mme Lavoie.
    /// Dates relatives à maintenant pour que les créneaux soient toujours à venir.
    static func demo(behavior: FakeBehavior) -> FakeVolunteerDeliveryRepository {
        let now = Date.now
        let hour: TimeInterval = 3_600
        let tomorrow = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * hour)
        func window(_ startHour: Double, _ length: Double = 2) -> VolunteerDelivery.Window {
            let start = tomorrow.addingTimeInterval(startHour * hour)
            return .init(start: start, end: start.addingTimeInterval(length * hour))
        }
        func request(
            _ index: Int, name: String, geohash: String, quantity: Int, window: VolunteerDelivery.Window,
            reason: VolunteerDelivery.Reason, note: String?
        ) -> VolunteerDelivery.Request {
            VolunteerDelivery.Request(
                id: "delivery-demo-\(index)", groupId: FakeData.ID.saintMichel, groupOrderId: FakeData.ID.potatoOrder,
                householdId: "household-voisin-\(index)", householdName: name, geohash: geohash, quantity: quantity,
                window: window, reason: reason, note: note, status: .requested, createdAt: now.addingTimeInterval(-Double(index) * hour)
            )
        }
        var lavoie = request(4, name: "Mme Lavoie", geohash: "f25dvq", quantity: 1, window: window(10),
                             reason: .senior, note: "Je suis là toute la matinée.")
        lavoie.status = .claimed
        lavoie.volunteerHouseholdId = FakeData.ID.aminaHousehold
        lavoie.volunteerName = "Amina"
        lavoie.claimedAt = now.addingTimeInterval(-hour)
        let requests = [
            request(1, name: "M. Gagnon", geohash: "f25dvk", quantity: 2, window: window(13),
                    reason: .senior, note: "Sonnez fort, j'entends mal."),
            request(2, name: "Mme Tremblay", geohash: "f25dvs", quantity: 1, window: window(15, 3),
                    reason: .reducedMobility, note: nil),
            request(3, name: "M. Nguyen", geohash: "f25dtz", quantity: 3, window: window(17.5),
                    reason: .senior, note: "Merci mille fois !"),
            lavoie,
        ]
        let addresses = [
            VolunteerDelivery.PrivateAddress(requestId: "delivery-demo-1", address: "8421, rue Pie-IX, app. 3",
                                             instructions: "Sonnette 3, 2e étage"),
            VolunteerDelivery.PrivateAddress(requestId: "delivery-demo-2", address: "3360, boulevard Robert",
                                             instructions: nil),
            VolunteerDelivery.PrivateAddress(requestId: "delivery-demo-3", address: "9115, 24e Avenue",
                                             instructions: "Porte de côté"),
            VolunteerDelivery.PrivateAddress(requestId: "delivery-demo-4", address: "7730, rue Lacordaire",
                                             instructions: "Entrée par la ruelle, porte verte"),
        ]
        return FakeVolunteerDeliveryRepository(behavior: behavior, requests: requests, addresses: addresses)
    }
}
