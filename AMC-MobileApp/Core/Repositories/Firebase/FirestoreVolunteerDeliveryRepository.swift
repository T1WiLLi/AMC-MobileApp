// FirestoreVolunteerDeliveryRepository.swift
// Dépôt Firestore des livraisons à domicile par un voisin bénévole (RQ-069, T-117).
//
//   groupOrders/{orderId}/deliveries/{requestId}                  demande, lisible par le groupe, sans adresse
//   groupOrders/{orderId}/deliveries/{requestId}/private/address  adresse : le ménage et son bénévole seulement
//
// Chaque changement d'état relit la demande DANS une transaction : deux voisins qui touchent « Je livre » en même
// temps → un seul gagne, l'autre reçoit « Un autre voisin a déjà pris cette livraison. ».
// Les règles métier restent celles de `VolunteerDelivery` ; firestore.rules les double côté serveur.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

nonisolated final class FirestoreVolunteerDeliveryRepository: VolunteerDeliveryRepository, @unchecked Sendable {
    private let db: Firestore
    private let now: @Sendable () -> Date

    /// À créer APRÈS `FirebaseApp.configure()`.
    init(db: Firestore = Firestore.firestore(), now: @escaping @Sendable () -> Date = { .now }) {
        self.db = db
        self.now = now
    }

    // MARK: - Références

    private func deliveriesRef(_ groupOrderId: String) -> CollectionReference {
        db.collection(FirestoreCollection.deliveries(ofGroupOrder: groupOrderId))
    }

    private func addressRef(_ groupOrderId: String, _ requestId: String) -> DocumentReference {
        db.collection(FirestoreCollection.deliveryPrivate(groupOrderId: groupOrderId, requestId: requestId))
            .document(FirestoreCollection.deliveryAddressDocumentId)
    }

    // MARK: - Lectures

    func deliveries(ofGroup groupId: String) async throws -> [VolunteerDelivery.Request] {
        do {
            // Par commande du groupe : pas d'index de groupe de collections à déclarer.
            let orders = try await db.collection(FirestoreCollection.groupOrders)
                .whereField("groupId", isEqualTo: groupId).getDocuments()
            var requests: [VolunteerDelivery.Request] = []
            for order in orders.documents {
                let snapshot = try await deliveriesRef(order.documentID).getDocuments()
                requests += try snapshot.documents.map(Self.decode)
            }
            return requests.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    func address(ofDelivery id: String, groupOrderId: String, viewerHouseholdId: String) async throws
        -> VolunteerDelivery.PrivateAddress? {
        do {
            let snapshot = try await deliveriesRef(groupOrderId).document(id).getDocument()
            guard snapshot.exists else { throw AppError.notFound }
            let request = try Self.decode(snapshot)
            guard VolunteerDelivery.canSeeAddress(request, viewerHouseholdId: viewerHouseholdId) else { return nil }
            let address = try await addressRef(groupOrderId, id).getDocument()
            guard address.exists else { return nil }
            return try FirestoreTransactions.decode(VolunteerDelivery.PrivateAddress.self, address, idKey: "requestId")
                .withRequestId(id)
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    // MARK: - Écritures

    @discardableResult
    func createDelivery(
        _ request: VolunteerDelivery.Request, address: VolunteerDelivery.PrivateAddress
    ) async throws -> VolunteerDelivery.Request {
        guard address.requestId == request.id else { throw AppError.invalidInput("Adresse d'une autre demande.") }
        let ref = deliveriesRef(request.groupOrderId).document(request.id)
        do {
            let mine = try await deliveriesRef(request.groupOrderId)
                .whereField("householdId", isEqualTo: request.householdId).getDocuments()
            if try mine.documents.map(Self.decode).contains(where: { !$0.status.isFinished }) {
                throw AppError.invalidInput("Tu as déjà une demande de livraison pour cette commande.")
            }
            var created = request
            created.status = .requested
            let addressRef = addressRef(request.groupOrderId, request.id)
            let requestData = try Firestore.Encoder().encode(created)
            let addressData = try Firestore.Encoder().encode(address)
            return try await FirestoreTransactions.run(db) { transaction in
                guard try !transaction.getDocument(ref).exists else {
                    throw AppError.invalidInput("Cette demande existe déjà.")
                }
                transaction.setData(requestData, forDocument: ref)
                transaction.setData(addressData, forDocument: addressRef)
                return created
            }
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    @discardableResult
    func claimDelivery(
        id: String, groupOrderId: String, volunteerHouseholdId: String, volunteerName: String,
        volunteerGroupIds: Set<String>
    ) async throws -> VolunteerDelivery.Request {
        let ref = deliveriesRef(groupOrderId).document(id)
        do {
            // Les livraisons en cours du bénévole (limite de 3, créneaux qui se chevauchent) sont relues
            // dans la transaction pour qu'un double clic sur deux demandes ne contourne pas la limite.
            let groupId = try Self.decode(try await ref.getDocument()).groupId
            let mineRefs = try await deliveries(ofGroup: groupId)
                .filter { $0.volunteerHouseholdId == volunteerHouseholdId && $0.status.isActive && $0.id != id }
                .map { deliveriesRef($0.groupOrderId).document($0.id) }
            let now = now()
            return try await FirestoreTransactions.run(db) { transaction in
                let current = try Self.decode(try transaction.getDocument(ref))
                let mine = try mineRefs.map { try Self.decode(try transaction.getDocument($0)) }
                let claimed = try VolunteerDelivery.claim(
                    current, volunteerHouseholdId: volunteerHouseholdId, volunteerName: volunteerName,
                    volunteerGroupIds: volunteerGroupIds, all: mine + [current], now: now
                )
                transaction.setData(try Firestore.Encoder().encode(claimed), forDocument: ref)
                return claimed
            }
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    @discardableResult
    func releaseDelivery(id: String, groupOrderId: String, volunteerHouseholdId: String) async throws
        -> VolunteerDelivery.Request {
        try await update(id, groupOrderId) { request, _ in
            try VolunteerDelivery.release(request, by: volunteerHouseholdId)
        }
    }

    @discardableResult
    func startRoute(id: String, groupOrderId: String, volunteerHouseholdId: String) async throws
        -> VolunteerDelivery.Request {
        let ref = deliveriesRef(groupOrderId).document(id)
        let orderRef = db.collection(FirestoreCollection.groupOrders).document(groupOrderId)
        let now = now()
        do {
            return try await FirestoreTransactions.run(db) { transaction in
                let request = try Self.decode(try transaction.getDocument(ref))
                let order = try FirestoreTransactions.decode(GroupOrder.self, try transaction.getDocument(orderRef))
                let shareRef = self.db.collection(FirestoreCollection.shares(ofGroupOrder: groupOrderId))
                    .document(request.householdId)
                let shareSnapshot = try transaction.getDocument(shareRef)
                let shares = shareSnapshot.exists
                    ? [try FirestoreTransactions.decode(Share.self, shareSnapshot, idKey: "householdId")] : []
                let (started, _) = try VolunteerDelivery.startRoute(
                    request, by: volunteerHouseholdId, order: order, shares: shares, now: now
                )
                transaction.setData(try Firestore.Encoder().encode(started), forDocument: ref)
                // Même écriture que la cueillette chez l'hôte (`PickupDesk.scan`).
                transaction.updateData(["isPickedUp": true, "updatedAt": Timestamp(date: now)], forDocument: shareRef)
                return started
            }
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    @discardableResult
    func markDelivered(id: String, groupOrderId: String, volunteerHouseholdId: String) async throws
        -> VolunteerDelivery.Request {
        try await update(id, groupOrderId) { request, now in
            try VolunteerDelivery.deliver(request, by: volunteerHouseholdId, now: now)
        }
    }

    @discardableResult
    func confirmReceipt(id: String, groupOrderId: String, householdId: String) async throws
        -> VolunteerDelivery.Request {
        try await update(id, groupOrderId) { request, now in
            try VolunteerDelivery.confirmReceipt(request, by: householdId, now: now)
        }
    }

    @discardableResult
    func cancelDelivery(id: String, groupOrderId: String, householdId: String) async throws
        -> VolunteerDelivery.Request {
        try await update(id, groupOrderId) { request, now in
            try VolunteerDelivery.cancel(request, by: householdId, now: now)
        }
    }

    // MARK: - Interne

    /// Lit la demande, applique la règle métier et réécrit le document, en transaction.
    private func update(
        _ id: String, _ groupOrderId: String,
        _ transform: @escaping @Sendable (VolunteerDelivery.Request, Date) throws -> VolunteerDelivery.Request
    ) async throws -> VolunteerDelivery.Request {
        let ref = deliveriesRef(groupOrderId).document(id)
        let now = now()
        do {
            return try await FirestoreTransactions.run(db) { transaction in
                let snapshot = try transaction.getDocument(ref)
                guard snapshot.exists else { throw AppError.notFound }
                let updated = try transform(try Self.decode(snapshot), now)
                transaction.setData(try Firestore.Encoder().encode(updated), forDocument: ref)
                return updated
            }
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    private static func decode(_ snapshot: DocumentSnapshot) throws -> VolunteerDelivery.Request {
        guard snapshot.exists else { throw AppError.notFound }
        return try FirestoreTransactions.decode(VolunteerDelivery.Request.self, snapshot)
    }
}

private nonisolated extension VolunteerDelivery.PrivateAddress {
    /// Le document s'appelle « address » : l'id de la demande vient du chemin, pas du nom du document.
    func withRequestId(_ id: String) -> Self {
        var copy = self
        copy.requestId = id
        return copy
    }
}
#endif
