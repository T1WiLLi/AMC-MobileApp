// FirestoreOrganizationRepository.swift
// Dépôt Firestore du portail Organismes (T-116, RQ-081). Même comportement que `FakeOrganizationRepository`.
//
// Collections :
//   - `organizations/{orgId}`                         (lecture : membres de l'organisme)
//   - `organizations/{orgId}/sponsorships/{groupId}`  (écriture : membres de l'organisme)
//   - `organizations/{orgId}/donations/{donationId}`  (création seule : membres de l'organisme)
//   - `groups/{groupId}/solidarity/fund`              (fonds anonyme ; un organisme n'y ajoute qu'une contribution)
// Un financement est une transaction : lecture du groupe et du fonds, contribution ajoutée par `OrganizationLedger`,
// trace du don écrite dans la même transaction. Paiements simulés : aucun argent réel.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

nonisolated final class FirestoreOrganizationRepository: OrganizationRepository, @unchecked Sendable {
    private let db: Firestore

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    private var organizationsRef: CollectionReference { db.collection(FirestoreCollection.organizations) }
    private var groupsRef: CollectionReference { db.collection(FirestoreCollection.groups) }

    private func fundRef(_ groupId: String) -> DocumentReference {
        db.collection(FirestoreCollection.solidarity(ofGroup: groupId))
            .document(FirestoreCollection.solidarityFundDocumentId)
    }

    private func sponsorshipsRef(_ organizationId: String) -> CollectionReference {
        db.collection(FirestoreCollection.sponsorships(ofOrganization: organizationId))
    }

    private func donationsRef(_ organizationId: String) -> CollectionReference {
        db.collection(FirestoreCollection.donations(ofOrganization: organizationId))
    }

    // MARK: - Lecture

    // Un id vide ferait planter Firestore (« Document path cannot be empty ») : on répond « introuvable ».
    func organization(id: String) async throws -> Organization {
        guard !id.isEmpty else { throw AppError.notFound }
        return try await FirestoreVendorRepository.fetchOne(Organization.self, organizationsRef.document(id))
    }

    func solidarityProfiles() async throws -> [GroupSolidarityProfile] {
        let groups = try await FirestoreVendorRepository.fetch(
            NeighborhoodGroup.self, groupsRef.whereField("isPublic", isEqualTo: true)
        )
        var profiles: [GroupSolidarityProfile] = []
        for group in groups {
            profiles.append(Self.profile(group, fund: try await fundDocument(group.id)))
        }
        return profiles.sorted { $0.groupName.localizedStandardCompare($1.groupName) == .orderedAscending }
    }

    func solidarityProfile(groupId: String) async throws -> GroupSolidarityProfile {
        let group = try await FirestoreVendorRepository.fetchOne(NeighborhoodGroup.self, groupsRef.document(groupId))
        return Self.profile(group, fund: try await fundDocument(groupId))
    }

    func donations(ofOrganization organizationId: String) async throws -> [OrganizationDonation] {
        guard !organizationId.isEmpty else { throw AppError.notFound }
        return try await FirestoreVendorRepository.fetch(OrganizationDonation.self, donationsRef(organizationId))
            .sorted { $0.date > $1.date }
    }

    func sponsorships(ofOrganization organizationId: String) async throws -> [Sponsorship] {
        guard !organizationId.isEmpty else { throw AppError.notFound }
        return try await FirestoreVendorRepository.fetch(Sponsorship.self, sponsorshipsRef(organizationId))
            .sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: - Écriture

    @discardableResult
    func donate(_ request: DonationRequest, toGroup groupId: String, organizationId: String) async throws -> OrganizationDonation {
        let groupRef = groupsRef.document(groupId)
        let fundRef = fundRef(groupId)
        let organizationRef = organizationsRef.document(organizationId)
        let donationRef = donationsRef(organizationId).document()
        let now = Date.now

        return try await runTransaction { transaction in
            let organizationSnapshot = try transaction.getDocument(organizationRef)
            guard organizationSnapshot.exists else { throw AppError.notFound }
            let groupSnapshot = try transaction.getDocument(groupRef)
            guard groupSnapshot.exists else { throw AppError.notFound }
            let group = try FirestoreVendorRepository.decode(NeighborhoodGroup.self, groupSnapshot)
            let fundSnapshot = try transaction.getDocument(fundRef)
            var fundDocument = fundSnapshot.exists
                ? try fundSnapshot.data(as: SolidarityFundDocument.self)
                : SolidarityFundDocument()

            let (donation, fund) = try OrganizationLedger.record(
                request, to: Self.profile(group, fund: fundDocument),
                organizationId: organizationId, donationId: donationRef.documentID, date: now
            )
            fundDocument.entries = fund.entries
            transaction.setData(try Firestore.Encoder().encode(fundDocument), forDocument: fundRef)
            transaction.setData(try Firestore.Encoder().encode(donation), forDocument: donationRef)
            return donation
        }
    }

    @discardableResult
    func sponsor(groupId: String, organizationId: String, monthlyBasketGoal: Int) async throws -> Sponsorship {
        guard monthlyBasketGoal > 0 else { throw AppError.invalidInput("Choisis un objectif d'au moins 1 panier par mois.") }
        let group = try await FirestoreVendorRepository.fetchOne(NeighborhoodGroup.self, groupsRef.document(groupId))
        let ref = sponsorshipsRef(organizationId).document(groupId)
        do {
            let existing = try await ref.getDocument()
            var sponsorship = existing.exists
                ? try FirestoreVendorRepository.decode(Sponsorship.self, existing)
                : Sponsorship(
                    id: groupId, organizationId: organizationId, groupName: group.name,
                    neighborhood: group.neighborhood, monthlyBasketGoal: monthlyBasketGoal, startedAt: .now
                )
            sponsorship.monthlyBasketGoal = monthlyBasketGoal
            let batch = db.batch()
            batch.setData(try Firestore.Encoder().encode(sponsorship), forDocument: ref)
            batch.setData(
                ["sponsorOrganizationIds": FieldValue.arrayUnion([organizationId])],
                forDocument: fundRef(groupId), merge: true
            )
            try await batch.commit()
            return sponsorship
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    func endSponsorship(groupId: String, organizationId: String) async throws {
        do {
            let batch = db.batch()
            batch.deleteDocument(sponsorshipsRef(organizationId).document(groupId))
            batch.setData(
                ["sponsorOrganizationIds": FieldValue.arrayRemove([organizationId])],
                forDocument: fundRef(groupId), merge: true
            )
            try await batch.commit()
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    // MARK: - Aides

    private func fundDocument(_ groupId: String) async throws -> SolidarityFundDocument {
        do {
            let snapshot = try await fundRef(groupId).getDocument()
            guard snapshot.exists else { return SolidarityFundDocument() }
            return try snapshot.data(as: SolidarityFundDocument.self)
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    private static func profile(_ group: NeighborhoodGroup, fund: SolidarityFundDocument) -> GroupSolidarityProfile {
        GroupSolidarityProfile(
            groupId: group.id, groupName: group.name, neighborhood: group.neighborhood,
            centerGeohash: group.centerGeohash, householdCount: group.householdCount,
            subsidizedHouseholds: fund.subsidizedHouseholds, basketPriceCents: fund.basketPriceCents,
            fund: fund.fund, sponsorOrganizationIds: fund.sponsorOrganizationIds
        )
    }

    /// Transaction Firestore en async : une erreur levée dans le bloc annule la transaction sans nouvel essai.
    private func runTransaction<Value>(_ block: @escaping (Transaction) throws -> Value) async throws -> Value {
        let box = OrganizationTransactionBox<Value>()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
            db.runTransaction({ transaction, errorPointer in
                box.value = nil
                box.error = nil
                do {
                    box.value = try block(transaction)
                } catch {
                    box.error = error
                    errorPointer?.pointee = error as NSError
                }
                return nil
            }, completion: { _, error in
                if let thrown = box.error {
                    continuation.resume(throwing: FirestoreGroupOrderRepository.appError(from: thrown))
                } else if let error {
                    continuation.resume(throwing: FirestoreGroupOrderRepository.appError(from: error))
                } else if let value = box.value {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(throwing: AppError.unknown("Transaction sans résultat."))
                }
            })
        }
    }
}

/// Résultat d'une transaction, passé du bloc (thread Firestore) à la complétion.
private nonisolated final class OrganizationTransactionBox<Value>: @unchecked Sendable {
    var value: Value?
    var error: (any Error)?
}
#endif
