// FirestoreGroupOrderRepository.swift
// Dépôt Firestore des commandes groupées (`groupOrders`) et des parts (`groupOrders/{id}/shares/{householdId}`) — B-019.
// Même comportement que `FakeGroupOrderRepository` : les ViewModels ne voient pas la différence.
//
// Invariant tenu par chaque transaction (et vérifié par `firestore.rules`) :
//   `committedShares` == somme des `quantity` des parts, `committedHouseholds` == nombre de parts.
// Une transaction Firestore côté client ne peut pas faire de requête : on lit la liste des parts
// avant, puis on relit chaque part DANS la transaction. Si la somme ne colle pas à `committedShares`
// (quelqu'un a ajouté une part entre-temps), on relit la liste et on recommence.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

/// Transporte un `ListenerRegistration` (non Sendable) dans `onTermination`.
/// Sûr : `remove()` est thread-safe et n'est appelé qu'une fois, à la fin du flux.
private nonisolated struct ListenerRegistrationBox: @unchecked Sendable {
    let registration: any ListenerRegistration
}

/// Résultat d'une transaction : le bloc peut tourner plusieurs fois, on garde le dernier passage.
/// Sûr : le bloc et la complétion s'exécutent l'un après l'autre, jamais en même temps.
private nonisolated final class TransactionOutcome<Value>: @unchecked Sendable {
    var value: Value?
    var error: (any Error)?
}

/// La liste des parts lue avant la transaction n'est plus à jour : on la relit.
private struct StaleShareList: Error {}

nonisolated final class FirestoreGroupOrderRepository: GroupOrderRepository, @unchecked Sendable {
    /// Clôture d'une commande : la commande figée et le résultat (prix, ou annulation).
    struct Closure: Sendable {
        var order: GroupOrder
        var outcome: TierEngine.ClosureOutcome
        /// Répartition entre les ménages ; nil si la commande est annulée (minimum non atteint).
        var allocation: ShareAllocator.Allocation?
    }

    private let db: Firestore
    private let now: @Sendable () -> Date
    /// Essais quand la liste des parts change pendant la transaction.
    private let maxAttempts = 5

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(db: Firestore = Firestore.firestore(), now: @escaping @Sendable () -> Date = { .now }) {
        self.db = db
        self.now = now
    }

    // MARK: - Références

    private var orders: CollectionReference { db.collection(FirestoreCollection.groupOrders) }
    private func orderRef(_ id: String) -> DocumentReference { orders.document(id) }
    private func sharesRef(_ orderId: String) -> CollectionReference {
        db.collection(FirestoreCollection.shares(ofGroupOrder: orderId))
    }
    private func offerRef(_ id: String) -> DocumentReference {
        db.collection(FirestoreCollection.offers).document(id)
    }

    // MARK: - Lectures

    func groupOrders(ofGroup groupId: String) async throws -> [GroupOrder] {
        try await PerfSignposts.measure("firestore.groupOrdersOfGroup") { try await query(orders.whereField("groupId", isEqualTo: groupId)) }
    }

    func groupOrders(ofOffer offerId: String) async throws -> [GroupOrder] {
        try await query(orders.whereField("offerId", isEqualTo: offerId))
    }

    func groupOrder(id: String) async throws -> GroupOrder {
        do {
            let snapshot = try await orderRef(id).getDocument()
            guard snapshot.exists else { throw AppError.notFound }
            return try Self.decodeOrder(snapshot)
        } catch {
            throw Self.appError(from: error)
        }
    }

    func shares(ofGroupOrder groupOrderId: String) async throws -> [Share] {
        _ = try await groupOrder(id: groupOrderId)
        return try await fetchShares(groupOrderId)
    }

    func observeGroupOrder(id: String) async -> AsyncThrowingStream<GroupOrder, any Error> {
        let (stream, continuation) = AsyncThrowingStream<GroupOrder, any Error>.makeStream()
        let firstSnapshot = PerfSignposts.begin("firestore.observeGroupOrder.firstSnapshot")
        let registration = orderRef(id).addSnapshotListener { snapshot, error in
            firstSnapshot.end(failed: error != nil)
            if let error {
                continuation.finish(throwing: Self.appError(from: error))
                return
            }
            guard let snapshot, snapshot.exists else {
                continuation.finish(throwing: AppError.notFound)
                return
            }
            do {
                continuation.yield(try Self.decodeOrder(snapshot))
            } catch {
                continuation.finish(throwing: Self.appError(from: error))
            }
        }
        // Le listener est retiré dès que le flux se termine (vue fermée, tâche annulée, erreur).
        let box = ListenerRegistrationBox(registration: registration)
        continuation.onTermination = { _ in box.registration.remove() }
        return stream
    }

    // MARK: - Écritures

    @discardableResult
    func openGroupOrder(groupId: String, offerId: String) async throws -> GroupOrder {
        // Déjà une commande ouverte du groupe sur ce lot ?
        let existing = try await query(
            orders.whereField("groupId", isEqualTo: groupId).whereField("offerId", isEqualTo: offerId)
        )
        if let open = existing.first(where: TierEngine.isOpen) { return open }

        // Sinon on la crée, avec un id déterministe : deux familles qui ouvrent en même temps
        // tombent sur le même document, la seconde le relit au lieu d'en créer un autre.
        let now = now()
        let candidates = [Self.orderId(groupId: groupId, offerId: offerId)]
            + (2...20).map { "\(Self.orderId(groupId: groupId, offerId: offerId))-\($0)" }
        let offerRef = offerRef(offerId)
        let orderRefs = candidates.map(orderRef)
        return try await runTransaction { transaction in
            let offerSnapshot = try transaction.getDocument(offerRef)
            guard offerSnapshot.exists else { throw AppError.notFound }
            let offer = try Self.decodeOffer(offerSnapshot)
            for ref in orderRefs {
                let snapshot = try transaction.getDocument(ref)
                if snapshot.exists {
                    let order = try Self.decodeOrder(snapshot)
                    if TierEngine.isOpen(order) { return order }
                    continue // Commande fermée sur ce lot : on prend l'id suivant.
                }
                guard offer.status == .active, offer.deadline > now else { throw AppError.orderClosed }
                let order = GroupOrder(
                    id: ref.documentID, groupId: groupId, offerId: offerId, status: .open,
                    currentTierIndex: nil, committedShares: 0, committedHouseholds: 0,
                    pickupPointId: nil, pickupSlots: []
                )
                transaction.setData(try Firestore.Encoder().encode(order), forDocument: ref)
                return order
            }
            throw AppError.unknown("Trop de commandes fermées pour ce groupe et ce lot.")
        }
    }

    @discardableResult
    func setShare(quantity: Int, householdId: String, groupOrderId: String) async throws -> GroupOrder {
        guard quantity >= 0 else { throw AppError.invalidInput("La quantité ne peut pas être négative.") }
        let orderRef = orderRef(groupOrderId)
        let shareRef = sharesRef(groupOrderId).document(householdId)

        return try await withFreshShareList(groupOrderId) { knownIds in
            let shareRefs = knownIds.filter { $0 != householdId }.map { self.sharesRef(groupOrderId).document($0) }
            let now = self.now()
            return try await self.runTransaction { transaction in
                let (order, offer, others) = try Self.readOrder(
                    orderRef, shares: shareRefs, offerRef: self.offerRef, in: transaction
                )
                let mineSnapshot = try transaction.getDocument(shareRef)
                let mine = mineSnapshot.exists ? try Self.decodeShare(mineSnapshot) : nil

                // L'invariant doit tenir AVANT d'écrire, sinon on a raté une part.
                try Self.checkInvariant(order, shares: others + [mine].compactMap { $0 })

                guard TierEngine.isOpen(order), now < offer.deadline else { throw AppError.orderClosed }
                let othersTotal = others.reduce(0) { $0 + $1.quantity }
                guard othersTotal + quantity <= offer.totalShares else {
                    throw AppError.invalidInput("Il ne reste que \(offer.totalShares - othersTotal) parts dans ce lot.")
                }

                var newShares = others
                if quantity > 0 {
                    var share = mine ?? Share(
                        householdId: householdId, quantity: quantity, finalPriceCents: nil, isPaid: false,
                        suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false
                    )
                    share.quantity = quantity
                    share.updatedAt = now
                    newShares.append(share)
                    if mine == nil {
                        transaction.setData(try Firestore.Encoder().encode(share), forDocument: shareRef)
                    } else {
                        // Seuls les champs qui changent : réécrire toute la part ferait bouger les dates
                        // (aller-retour Date ↔ Timestamp) et les null du seed, et firestore.rules refuserait.
                        transaction.updateData(
                            ["quantity": quantity, "updatedAt": Timestamp(date: now)], forDocument: shareRef
                        )
                    }
                } else if mine != nil {
                    transaction.deleteDocument(shareRef)
                }
                // Même recalcul que le fake (RQ-051) : quantité, ménages, palier et statut.
                let updated = try TierEngine.recalculated(order, offer: offer, shares: newShares)
                transaction.updateData(Self.counterFields(updated), forDocument: orderRef)
                return updated
            }
        }
    }

    /// RQ-053, RQ-054 : clôture la commande après la date limite (coordonnateur du groupe ou vendeur du lot).
    /// Palier figé par `TierEngine.closed`, puis prix final, subvention et code QR de chaque part
    /// par `ShareAllocator`. Lève `.orderClosed` si elle est déjà fermée, `.invalidInput` avant la date limite.
    @discardableResult
    func closeGroupOrder(
        id groupOrderId: String,
        eligibleHouseholdIds: Set<String> = [],
        solidarityFundCents: Cents = 0
    ) async throws -> Closure {
        let orderRef = orderRef(groupOrderId)
        return try await withFreshShareList(groupOrderId) { knownIds in
            let shareRefs = knownIds.map { self.sharesRef(groupOrderId).document($0) }
            let now = self.now()
            return try await self.runTransaction { transaction in
                let (order, offer, shares) = try Self.readOrder(
                    orderRef, shares: shareRefs, offerRef: self.offerRef, in: transaction
                )
                try Self.checkInvariant(order, shares: shares)
                guard TierEngine.isOpen(order) else { throw AppError.orderClosed }
                guard TierEngine.shouldClose(order, offer: offer, now: now) else {
                    throw AppError.invalidInput("La commande se clôture à la date limite du lot.")
                }

                let (closed, outcome) = try TierEngine.closed(order, offer: offer)
                var allocation: ShareAllocator.Allocation?
                if case .confirmed(_, let unitPriceCents) = outcome {
                    let result = try ShareAllocator.allocate(
                        orderId: groupOrderId, offer: offer, shares: shares, unitPriceCents: unitPriceCents,
                        eligibleHouseholdIds: eligibleHouseholdIds, solidarityFundCents: solidarityFundCents
                    )
                    for share in result.shares {
                        transaction.updateData([
                            "finalPriceCents": share.finalPriceCents.map { $0 as Any } ?? NSNull(),
                            "subsidyCents": share.subsidyCents,
                            "qrCode": share.qrCode.map { $0 as Any } ?? NSNull(),
                        ], forDocument: self.sharesRef(groupOrderId).document(share.householdId))
                    }
                    allocation = result
                }
                transaction.updateData(Self.counterFields(closed), forDocument: orderRef)
                return Closure(order: closed, outcome: outcome, allocation: allocation)
            }
        }
    }

    // MARK: - Transactions

    /// Lit la liste des parts, lance `body`, et recommence si la liste a changé pendant la transaction.
    private func withFreshShareList<Value>(
        _ groupOrderId: String,
        _ body: ([String]) async throws -> Value
    ) async throws -> Value {
        for _ in 0..<maxAttempts {
            let ids: [String]
            do {
                ids = try await sharesRef(groupOrderId).getDocuments().documents.map(\.documentID)
            } catch {
                throw Self.appError(from: error)
            }
            do {
                return try await body(ids)
            } catch is StaleShareList {
                continue
            }
        }
        throw AppError.unknown("Trop de changements simultanés sur cette commande, réessaie.")
    }

    /// `runTransaction` avec un bloc qui lève des erreurs Swift (`AppError`, `StaleShareList`).
    /// Le bloc peut tourner plusieurs fois (conflit) : il ne doit rien faire d'autre que lire et écrire.
    private func runTransaction<Value>(
        _ block: @escaping (Transaction) throws -> Value
    ) async throws -> Value {
        let outcome = TransactionOutcome<Value>()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
            db.runTransaction({ transaction, errorPointer in
                outcome.value = nil
                outcome.error = nil
                do {
                    outcome.value = try block(transaction)
                } catch {
                    // Une erreur posée ici annule la transaction sans nouvel essai.
                    outcome.error = error
                    errorPointer?.pointee = error as NSError
                }
                return nil
            }, completion: { _, error in
                if let thrown = outcome.error {
                    continuation.resume(throwing: thrown is StaleShareList ? thrown : Self.appError(from: thrown))
                } else if let error {
                    continuation.resume(throwing: Self.appError(from: error))
                } else if let value = outcome.value {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(throwing: AppError.unknown("Transaction sans résultat."))
                }
            })
        }
    }

    /// Lit la commande, son lot et les parts données, dans la transaction.
    private static func readOrder(
        _ orderRef: DocumentReference,
        shares shareRefs: [DocumentReference],
        offerRef: (String) -> DocumentReference,
        in transaction: Transaction
    ) throws -> (GroupOrder, Offer, [Share]) {
        let orderSnapshot = try transaction.getDocument(orderRef)
        guard orderSnapshot.exists else { throw AppError.notFound }
        let order = try decodeOrder(orderSnapshot)
        let offerSnapshot = try transaction.getDocument(offerRef(order.offerId))
        guard offerSnapshot.exists else { throw AppError.notFound }
        let offer = try decodeOffer(offerSnapshot)
        var shares: [Share] = []
        for ref in shareRefs {
            let snapshot = try transaction.getDocument(ref)
            if snapshot.exists { shares.append(try decodeShare(snapshot)) }
        }
        return (order, offer, shares)
    }

    /// Champs d'une commande que recalculent `TierEngine.recalculated` et `TierEngine.closed`.
    /// On n'écrit qu'eux (pas `pickupSlots`, `pickupPointId`) : voir `setShare`.
    private static func counterFields(_ order: GroupOrder) -> [String: Any] {
        [
            "committedShares": order.committedShares,
            "committedHouseholds": order.committedHouseholds,
            "currentTierIndex": order.currentTierIndex.map { $0 as Any } ?? FieldValue.delete(),
            "status": order.status.rawValue,
        ]
    }

    /// Les parts lues expliquent-elles tout `committedShares` ? Sinon une part a été ajoutée entre-temps.
    private static func checkInvariant(_ order: GroupOrder, shares: [Share]) throws {
        let total = shares.reduce(0) { $0 + $1.quantity }
        let households = shares.filter { $0.quantity > 0 }.count
        if total != order.committedShares || households != order.committedHouseholds {
            throw StaleShareList()
        }
    }

    // MARK: - Cueillette (T-077)

    /// RQ-063 : point et créneaux choisis par le coordonnateur (`firestore.rules` le vérifie).
    /// Les réservations sur un créneau retiré sont effacées dans le même lot d'écritures.
    @discardableResult
    func setPickupPoint(_ pickupPointId: String?, slots: [PickupSlot], groupOrderId: String) async throws -> GroupOrder {
        var order = try await groupOrder(id: groupOrderId)
        guard order.status != .cancelled, order.status != .delivered else { throw AppError.orderClosed }
        let slots = pickupPointId == nil ? [] : try PickupSlotBook.validatedSlots(slots)
        let shares = try await fetchShares(groupOrderId)
        do {
            let batch = db.batch()
            let encodedSlots = try slots.map { try Firestore.Encoder().encode($0) }
            batch.updateData([
                "pickupPointId": pickupPointId.map { $0 as Any } ?? NSNull(),
                "pickupSlots": encodedSlots,
            ], forDocument: orderRef(groupOrderId))
            let cleared = PickupSlotBook.clearingRemovedSlots(shares, keeping: slots)
            for (before, after) in zip(shares, cleared) where before.pickupSlotStart != after.pickupSlotStart {
                batch.updateData(["pickupSlotStart": FieldValue.delete()],
                                 forDocument: sharesRef(groupOrderId).document(before.householdId))
            }
            try await batch.commit()
        } catch {
            throw Self.appError(from: error)
        }
        order.pickupPointId = pickupPointId
        order.pickupSlots = slots
        return order
    }

    /// RQ-064 : créneau du ménage. La capacité est vérifiée sur les parts lues juste avant
    /// (pas de transaction : un dépassement d'une place reste possible si deux ménages réservent en même temps).
    @discardableResult
    func reservePickupSlot(start: Date?, householdId: String, groupOrderId: String) async throws -> Share {
        let order = try await groupOrder(id: groupOrderId)
        guard order.status != .cancelled, order.status != .delivered else { throw AppError.orderClosed }
        let shares = try await fetchShares(groupOrderId)
        let share = try PickupSlotBook.reserving(
            start, householdId: householdId, slots: order.pickupSlots, shares: shares, now: now()
        )
        do {
            let value: Any = share.pickupSlotStart.map { Timestamp(date: $0) as Any } ?? FieldValue.delete()
            try await sharesRef(groupOrderId).document(householdId).updateData(["pickupSlotStart": value])
        } catch {
            throw Self.appError(from: error)
        }
        return share
    }

    // MARK: - Requêtes et décodage

    private func query(_ query: Query) async throws -> [GroupOrder] {
        do {
            let snapshot = try await query.getDocuments()
            return try snapshot.documents.map(Self.decodeOrder).sorted { $0.id < $1.id }
        } catch {
            throw Self.appError(from: error)
        }
    }

    private func fetchShares(_ groupOrderId: String) async throws -> [Share] {
        do {
            let snapshot = try await sharesRef(groupOrderId).getDocuments()
            return try snapshot.documents.map(Self.decodeShare).sorted { $0.householdId < $1.householdId }
        } catch {
            throw Self.appError(from: error)
        }
    }

    /// Id d'une commande : `order-<groupe>-<lot>`, comme dans le fake.
    static func orderId(groupId: String, offerId: String) -> String { "order-\(groupId)-\(offerId)" }

    // L'id du document fait foi : un document écrit sans champ `id` (seed, console) se décode quand même.
    private static func decodeOrder(_ snapshot: DocumentSnapshot) throws -> GroupOrder {
        try decode(GroupOrder.self, snapshot, idKey: "id")
    }

    private static func decodeShare(_ snapshot: DocumentSnapshot) throws -> Share {
        try decode(Share.self, snapshot, idKey: "householdId")
    }

    private static func decodeOffer(_ snapshot: DocumentSnapshot) throws -> Offer {
        try decode(Offer.self, snapshot, idKey: "id")
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ snapshot: DocumentSnapshot, idKey: String) throws -> T {
        var data = snapshot.data() ?? [:]
        data[idKey] = snapshot.documentID
        do {
            return try Firestore.Decoder().decode(T.self, from: data)
        } catch {
            throw AppError.unknown("Document \(snapshot.reference.path) illisible : \(error.localizedDescription)")
        }
    }

    // MARK: - Erreurs

    /// Convertit une erreur Firestore (ou réseau) en `AppError`.
    static func appError(from error: any Error) -> AppError {
        if let appError = error as? AppError { return appError }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .offline }
        guard nsError.domain == FirestoreErrorDomain,
              let code = FirestoreErrorCode.Code(rawValue: nsError.code) else {
            return .unknown(nsError.localizedDescription)
        }
        switch code {
        case .permissionDenied: return .permissionDenied
        case .unauthenticated: return .unauthenticated
        case .notFound: return .notFound
        case .unavailable, .deadlineExceeded: return .offline
        case .invalidArgument, .outOfRange: return .invalidInput(nsError.localizedDescription)
        default: return .unknown(nsError.localizedDescription)
        }
    }
}
#endif
