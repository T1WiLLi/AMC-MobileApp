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
    private let db: Firestore
    private let now: @Sendable () -> Date
    /// E21-2 : faux terminal de paiement utilisé à la clôture (refus avec `-demoPaymentDeclined`).
    private let payments: PaymentSimulator
    /// Essais quand la liste des parts change pendant la transaction.
    private let maxAttempts = 5

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(
        db: Firestore = Firestore.firestore(),
        now: @escaping @Sendable () -> Date = { .now },
        payments: PaymentSimulator = .fromLaunchArguments()
    ) {
        self.db = db
        self.now = now
        self.payments = payments
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
    private func paymentsRef(_ orderId: String) -> CollectionReference {
        db.collection(FirestoreCollection.payments(ofGroupOrder: orderId))
    }
    private func payoutRef(_ orderId: String) -> DocumentReference {
        db.collection(FirestoreCollection.payouts(ofGroupOrder: orderId)).document(FirestoreCollection.vendorPayoutDocumentId)
    }
    private func fundRef(_ groupId: String) -> DocumentReference {
        db.collection(FirestoreCollection.solidarity(ofGroup: groupId)).document(FirestoreCollection.solidarityFundDocumentId)
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

    /// T-174 : lecture du seul document du ménage (les règles le laissent lire sa propre part, même hors du groupe).
    func share(ofHousehold householdId: String, inGroupOrder groupOrderId: String) async throws -> Share? {
        do {
            let snapshot = try await sharesRef(groupOrderId).document(householdId).getDocument()
            return snapshot.exists ? try Self.decodeShare(snapshot) : nil
        } catch {
            throw Self.appError(from: error)
        }
    }

    /// T-195 : paiements enregistrés à la clôture (firestore.rules : le vendeur du lot et la coordination les lisent tous).
    func payments(ofGroupOrder groupOrderId: String) async throws -> [PaymentRecord] {
        do {
            let snapshot = try await paymentsRef(groupOrderId).getDocuments()
            return try snapshot.documents.map { try $0.data(as: PaymentRecord.self) }.sorted { $0.householdId < $1.householdId }
        } catch {
            throw Self.appError(from: error)
        }
    }

    /// T-195 : récapitulatif du versement au vendeur, nil si la commande n'est pas fermée avec des paiements.
    func vendorPayout(ofGroupOrder groupOrderId: String) async throws -> VendorPayoutRecord? {
        do {
            let snapshot = try await payoutRef(groupOrderId).getDocument()
            return snapshot.exists ? try snapshot.data(as: VendorPayoutRecord.self) : nil
        } catch {
            throw Self.appError(from: error)
        }
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
        guard quantity >= 0 else { throw AppError.invalidInput(String(localized: "La quantité ne peut pas être négative.")) }
        let orderRef = orderRef(groupOrderId)
        let shareRef = sharesRef(groupOrderId).document(householdId)
        // Copié dans la part pour l'hôte, qui ne peut pas lire `households/{id}` ; jamais bloquant.
        let householdName = quantity > 0 ? await householdName(of: householdId) : nil
        // T-195 : statut subventionné de mon ménage, copié dans ma part pour la clôture (profil privé illisible d'ailleurs).
        let eligible = quantity > 0 ? await isSubsidized(householdId) : false

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
                    throw AppError.invalidInput(String(localized: "Il ne reste que \(offer.totalShares - othersTotal) parts dans ce lot."))
                }

                var newShares = others
                if quantity > 0 {
                    var share = mine ?? Share(
                        householdId: householdId, quantity: quantity, finalPriceCents: nil, isPaid: false,
                        suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false
                    )
                    share.quantity = quantity
                    share.updatedAt = now
                    if let householdName { share.householdName = householdName }
                    if eligible || mine?.solidarityEligible != nil { share.solidarityEligible = eligible }
                    newShares.append(share)
                    if mine == nil {
                        transaction.setData(try Firestore.Encoder().encode(share), forDocument: shareRef)
                    } else {
                        // Seuls les champs qui changent : réécrire toute la part ferait bouger les dates
                        // (aller-retour Date ↔ Timestamp) et les null du seed, et firestore.rules refuserait.
                        var fields: [String: Any] = ["quantity": quantity, "updatedAt": Timestamp(date: now)]
                        // Ancienne part sans nom (ou ménage renommé) : le nom suit le prochain changement.
                        if let householdName, mine?.householdName != householdName {
                            fields["householdName"] = householdName
                        }
                        if eligible != (mine?.solidarityEligible ?? false) { fields["solidarityEligible"] = eligible }
                        transaction.updateData(fields, forDocument: shareRef)
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

    /// Nom de mon ménage (`households/{id}.name`, lisible par ses membres), nil s'il est illisible.
    private func householdName(of householdId: String) async -> String? {
        let snapshot = try? await db.collection(FirestoreCollection.households).document(householdId).getDocument()
        return ShareHouseholdName.normalized(snapshot?.data()?["name"] as? String)
    }

    /// Statut subventionné de mon ménage (`households/{id}/private/profile`, code d'organisme valide), faux s'il est illisible.
    private func isSubsidized(_ householdId: String) async -> Bool {
        let path = FirestoreCollection.householdPrivate(householdId)
        guard let snapshot = try? await db.collection(path).document(FirestoreCollection.householdPrivateDocumentId).getDocument(),
              snapshot.exists, let profile = try? snapshot.data(as: HouseholdPrivate.self) else { return false }
        return ReferralCode.eligibleHouseholdIds([householdId: profile]).contains(householdId)
    }

    /// T-181 : panier suspendu de ma part, fixé à `amountCents`. Seuls `suspendedAmountCents` et `updatedAt` changent
    /// (firestore.rules : le ménage peut modifier ces champs d'une part tant que la commande est ouverte).
    @discardableResult
    func setSuspendedBasket(_ amountCents: Cents, householdId: String, groupOrderId: String) async throws -> Share {
        let order = try await groupOrder(id: groupOrderId)
        let shareRef = sharesRef(groupOrderId).document(householdId)
        let current: Share
        do {
            let snapshot = try await shareRef.getDocument()
            guard snapshot.exists else { throw AppError.notFound }
            current = try Self.decodeShare(snapshot)
        } catch let error as AppError {
            throw error
        } catch {
            throw Self.appError(from: error)
        }
        var updated = try SolidarityLedger.settingSuspendedBasket(amountCents, on: current, in: order)
        updated.updatedAt = now()
        do {
            try await shareRef.updateData(["suspendedAmountCents": amountCents, "updatedAt": Timestamp(date: now())])
        } catch {
            throw Self.appError(from: error)
        }
        return updated
    }

    /// RQ-053, RQ-054, E21-2, T-195 : clôture la commande (coordonnateur du groupe ou vendeur du lot, ou automatiquement
    /// après la date limite), voir `GroupOrderClosing.close`. Dans la même transaction : palier figé, prix final,
    /// subvention de chaque part (`ShareAllocator`), paiement simulé de chaque part au pot (`isPaid` à true
    /// si le paiement réussit), un `PaymentRecord` par part payée (`groupOrders/{id}/payments/{householdId}`), le
    /// récapitulatif du versement au vendeur (`payouts/vendor`) et le débit du fonds de solidarité
    /// (`groups/{g}/solidarity/fund`, jamais sous zéro). `eligibleHouseholdIds` s'ajoute aux ménages qui se sont déclarés
    /// admissibles dans leur part ; le solde du fonds est lu dans la transaction (`solidarityFundCents` ne sert que
    /// s'il n'y a pas de document de fonds). Lève `.orderClosed` si elle est déjà fermée.
    @discardableResult
    func closeGroupOrder(
        id groupOrderId: String,
        trigger: GroupOrderClosureTrigger,
        eligibleHouseholdIds: Set<String>,
        solidarityFundCents: Cents
    ) async throws -> GroupOrderClosure {
        let orderRef = orderRef(groupOrderId)
        let payments = payments
        return try await withFreshShareList(groupOrderId) { knownIds in
            let shareRefs = knownIds.map { self.sharesRef(groupOrderId).document($0) }
            let now = self.now()
            return try await self.runTransaction { transaction in
                let (order, offer, shares) = try Self.readOrder(
                    orderRef, shares: shareRefs, offerRef: self.offerRef, in: transaction
                )
                try Self.checkInvariant(order, shares: shares)
                // Toutes les lectures avant la première écriture (règle des transactions Firestore).
                let fundRef = self.fundRef(order.groupId)
                let fundSnapshot = try transaction.getDocument(fundRef)
                let fundDocument = fundSnapshot.exists ? try? fundSnapshot.data(as: SolidarityFundDocument.self) : nil
                let vendorSnapshot = try transaction.getDocument(
                    self.db.collection(FirestoreCollection.vendors).document(offer.vendorId)
                )
                let vendorIsVerified = vendorSnapshot.data()?["isVerified"] as? Bool ?? false

                let closure = try GroupOrderClosing.close(
                    order: order, offer: offer, shares: shares, trigger: trigger, now: now,
                    eligibleHouseholdIds: eligibleHouseholdIds, solidarityFundCents: solidarityFundCents,
                    fund: fundDocument?.fund, vendorIsVerified: vendorIsVerified, payments: payments
                )
                let wasPaid = Set(shares.filter(\.isPaid).map(\.householdId))
                for share in closure.shares {
                    var fields: [String: Any] = [
                        "finalPriceCents": share.finalPriceCents.map { $0 as Any } ?? NSNull(),
                        "subsidyCents": share.subsidyCents,
                        // Pas de qrCode : la part est lisible par tout le groupe, le jeton est privé (`pickupCode`).
                    ]
                    // Paiement simulé réussi : seul passage de `isPaid` à true (firestore.rules, clôture).
                    if share.isPaid, !wasPaid.contains(share.householdId) { fields["isPaid"] = true }
                    transaction.updateData(fields, forDocument: self.sharesRef(groupOrderId).document(share.householdId))
                }
                // T-195 : un paiement enregistré par part payée, jamais modifié ensuite (firestore.rules).
                for record in closure.payments where record.status == .succeeded {
                    transaction.setData(
                        try Firestore.Encoder().encode(record),
                        forDocument: self.paymentsRef(groupOrderId).document(record.householdId)
                    )
                }
                if let payout = closure.vendorPayout, closure.isConfirmed {
                    transaction.setData(try Firestore.Encoder().encode(payout), forDocument: self.payoutRef(groupOrderId))
                }
                if let entry = closure.fundEntry, fundDocument != nil {
                    // arrayUnion : les écritures déjà là ne sont pas réécrites (firestore.rules, isClosureDebit).
                    transaction.updateData([
                        "entries": FieldValue.arrayUnion([try Firestore.Encoder().encode(entry)]),
                    ], forDocument: fundRef)
                }
                transaction.updateData(Self.counterFields(closure.order), forDocument: orderRef)
                return closure
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

    /// « La livraison est arrivée » : seuls `status` et `deliveredAt` changent (firestore.rules,
    /// `isArrivalUpdate` : coordonnateur du groupe ou hôte du point, commande fermée, `deliveredAt == request.time`).
    @discardableResult
    func markArrived(groupOrderId: String, at date: Date) async throws -> GroupOrder {
        let order = try await groupOrder(id: groupOrderId)
        let delivered = try OrderArrival.markArrived(order, at: date)
        do {
            try await orderRef(groupOrderId).updateData([
                "status": GroupOrder.Status.delivered.rawValue,
                "deliveredAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            throw Self.appError(from: error)
        }
        return delivered
    }

    /// T-159 : une transaction relit la part avant de la marquer : deux scans en même temps n'en remettent qu'un.
    /// Sécurité : elle relit aussi le jeton privé du ménage (`private/pickup`, lisible par l'hôte du point et les
    /// coordonnateurs) ; un code qui ne le porte pas est refusé (`.unknownCode`, ancien code : `.outdatedCode`).
    func confirmPickup(code: String, groupOrderId: String, at date: Date) async throws -> PickupDesk.ScanResult {
        let order = try await groupOrder(id: groupOrderId)
        // QR d'un groupe (T-198) : seul le code de cette commande compte.
        let code = PickupDesk.code(for: groupOrderId, in: code)
        guard PickupDesk.canPickUp(order.status), let parsed = PickupDesk.parse(code),
              parsed.orderId == groupOrderId, !parsed.isLegacy else {
            return PickupDesk.scan(code, order: order, shares: [], pickupTokens: [:], at: date)
        }
        let shareRef = sharesRef(groupOrderId).document(parsed.householdId)
        let tokenRef = pickupTokenRef(groupOrderId, householdId: parsed.householdId)
        return try await runTransaction { transaction in
            let snapshot = try transaction.getDocument(shareRef)
            let tokenSnapshot = try transaction.getDocument(tokenRef)
            let shares = snapshot.exists ? [try Self.decodeShare(snapshot)] : []
            let tokens = (tokenSnapshot.data()?["code"] as? String).map { [parsed.householdId: $0] } ?? [:]
            let result = PickupDesk.scan(code, order: order, shares: shares, pickupTokens: tokens, at: date)
            if case .pickedUp(let share) = result {
                transaction.updateData(Self.pickupFields(share, at: date), forDocument: shareRef)
            }
            return result
        }
    }

    /// « Récupéré » sans code (`PickupDesk.handOver`) : `pickedUpBy` = l'hôte ou le coordonnateur qui confirme.
    @discardableResult
    func confirmPickupByHand(
        householdId: String, groupOrderId: String, confirmedBy: String, at date: Date
    ) async throws -> PickupDesk.ScanResult {
        let order = try await groupOrder(id: groupOrderId)
        guard PickupDesk.canPickUp(order.status), !householdId.isEmpty, !householdId.contains("/") else {
            return PickupDesk.handOver(householdId: householdId, order: order, shares: [], pickedUpBy: confirmedBy, at: date)
        }
        let shareRef = sharesRef(groupOrderId).document(householdId)
        return try await runTransaction { transaction in
            let snapshot = try transaction.getDocument(shareRef)
            let shares = snapshot.exists ? [try Self.decodeShare(snapshot)] : []
            let result = PickupDesk.handOver(householdId: householdId, order: order, shares: shares,
                                             pickedUpBy: confirmedBy, at: date)
            if case .pickedUp(let share) = result {
                transaction.updateData(Self.pickupFields(share, at: date), forDocument: shareRef)
            }
            return result
        }
    }

    /// Code de la part du ménage : relit son jeton privé, ou le crée (une seule fois : firestore.rules refuse
    /// de le réécrire ; deux membres en même temps → la transaction relit celui de l'autre).
    func pickupCode(householdId: String, groupOrderId: String) async throws -> String {
        guard !householdId.isEmpty, !householdId.contains("/") else { throw AppError.notFound }
        let shareRef = sharesRef(groupOrderId).document(householdId)
        let tokenRef = pickupTokenRef(groupOrderId, householdId: householdId)
        let fresh = PickupDesk.newPickupToken()
        let createdAt = Timestamp(date: now())
        let token: String = try await runTransaction { transaction in
            let tokenSnapshot = try transaction.getDocument(tokenRef)
            if tokenSnapshot.exists {
                guard let code = tokenSnapshot.data()?["code"] as? String, PickupDesk.isPickupToken(code) else {
                    throw AppError.unknown("Code de cueillette illisible.")
                }
                return code
            }
            guard try transaction.getDocument(shareRef).exists else { throw AppError.notFound }
            transaction.setData(["code": fresh, "createdAt": createdAt], forDocument: tokenRef)
            return fresh
        }
        return PickupDesk.pickupCode(orderId: groupOrderId, householdId: householdId, token: token)
    }

    /// Champs d'une remise (firestore.rules, `isPickupConfirmation`) : `pickedUpBy` est obligatoire.
    private static func pickupFields(_ share: Share, at date: Date) -> [String: Any] {
        var data: [String: Any] = [
            "isPickedUp": true,
            "pickedUpAt": Timestamp(date: date),
            "updatedAt": Timestamp(date: date),
        ]
        if let memberId = share.pickedUpBy { data["pickedUpBy"] = memberId }
        return data
    }

    /// Jeton privé du code de cueillette d'un ménage (`groupOrders/{o}/shares/{h}/private/pickup`).
    private func pickupTokenRef(_ groupOrderId: String, householdId: String) -> DocumentReference {
        sharesRef(groupOrderId).document(householdId).collection("private").document("pickup")
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
