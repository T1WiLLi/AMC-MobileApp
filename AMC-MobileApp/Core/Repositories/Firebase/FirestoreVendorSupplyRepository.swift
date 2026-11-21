// FirestoreVendorSupplyRepository.swift
// Dépôt Firestore des disponibilités des vendeurs (`vendors/{vendorId}/supplies/{supplyId}`) — S-08.
// Même comportement que `FakeVendorSupplyRepository` : les ViewModels ne voient pas la différence.
// Droits (firestore.rules) : lecture par tout utilisateur connecté, écriture par le vendeur propriétaire seulement.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

/// Transporte un `ListenerRegistration` (non Sendable) dans `onTermination`.
/// Sûr : `remove()` est thread-safe et n'est appelé qu'une fois, à la fin du flux.
private nonisolated struct SupplyListenerBox: @unchecked Sendable {
    let registration: any ListenerRegistration
}

nonisolated final class FirestoreVendorSupplyRepository: VendorSupplyRepository, @unchecked Sendable {
    private let db: Firestore
    private let now: @Sendable () -> Date

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(db: Firestore = Firestore.firestore(), now: @escaping @Sendable () -> Date = { .now }) {
        self.db = db
        self.now = now
    }

    // MARK: - Références

    private func suppliesRef(_ vendorId: String) -> CollectionReference {
        db.collection(FirestoreCollection.supplies(ofVendor: vendorId))
    }

    // MARK: - Lectures

    func supplies(ofVendor vendorId: String) async throws -> [VendorSupply] {
        try await query(suppliesRef(vendorId))
    }

    func allSupplies() async throws -> [VendorSupply] {
        // Sans filtre : pas d'index de groupe de collections à déclarer ; filtrer côté client.
        try await query(db.collectionGroup(FirestoreCollection.supplies))
    }

    func observeSupplies(ofVendor vendorId: String) async -> AsyncThrowingStream<[VendorSupply], any Error> {
        let (stream, continuation) = AsyncThrowingStream<[VendorSupply], any Error>.makeStream()
        let registration = suppliesRef(vendorId).addSnapshotListener { snapshot, error in
            if let error {
                continuation.finish(throwing: Self.appError(from: error))
                return
            }
            guard let snapshot else { return }
            do {
                continuation.yield(try Self.sorted(snapshot.documents.map(Self.decode)))
            } catch {
                continuation.finish(throwing: Self.appError(from: error))
            }
        }
        // Le listener est retiré dès que le flux se termine (vue fermée, tâche annulée, erreur).
        let box = SupplyListenerBox(registration: registration)
        continuation.onTermination = { _ in box.registration.remove() }
        return stream
    }

    // MARK: - Écritures

    @discardableResult
    func addSupply(_ supply: VendorSupply) async throws -> VendorSupply {
        try supply.validate()
        let collection = suppliesRef(supply.vendorId)
        let ref = supply.id.isEmpty ? collection.document() : collection.document(supply.id)
        var created = supply
        created.id = ref.documentID
        created.createdAt = now()
        created.updatedAt = created.createdAt
        do {
            // Id choisi par l'appelant : ne pas écraser une disponibilité existante (un id auto est toujours neuf).
            if !supply.id.isEmpty, try await ref.getDocument().exists {
                throw AppError.invalidInput("Cette disponibilité existe déjà.")
            }
            try await ref.setData(try Firestore.Encoder().encode(created))
            return created
        } catch {
            throw Self.appError(from: error)
        }
    }

    @discardableResult
    func updateSupply(_ supply: VendorSupply) async throws -> VendorSupply {
        let ref = suppliesRef(supply.vendorId).document(supply.id)
        do {
            let snapshot = try await ref.getDocument()
            guard snapshot.exists else { throw AppError.notFound }
            let current = try Self.decode(snapshot)
            guard current.vendorId == supply.vendorId else { throw AppError.permissionDenied }
            try supply.validate()
            var updated = supply
            updated.createdAt = current.createdAt
            updated.updatedAt = now()
            try await ref.setData(try Firestore.Encoder().encode(updated))
            return updated
        } catch {
            throw Self.appError(from: error)
        }
    }

    func removeSupply(id: String, vendorId: String) async throws {
        let ref = suppliesRef(vendorId).document(id)
        do {
            guard try await ref.getDocument().exists else { throw AppError.notFound }
            try await ref.delete()
        } catch {
            throw Self.appError(from: error)
        }
    }

    // MARK: - Requêtes et décodage

    private func query(_ query: Query) async throws -> [VendorSupply] {
        do {
            let snapshot = try await query.getDocuments()
            return try Self.sorted(snapshot.documents.map(Self.decode))
        } catch {
            throw Self.appError(from: error)
        }
    }

    private static func sorted(_ supplies: [VendorSupply]) -> [VendorSupply] {
        supplies.sorted { $0.availableFrom != $1.availableFrom ? $0.availableFrom < $1.availableFrom : $0.id < $1.id }
    }

    // L'id du document fait foi : un document écrit sans champ `id` (seed, console) se décode quand même.
    private static func decode(_ snapshot: DocumentSnapshot) throws -> VendorSupply {
        var data = snapshot.data() ?? [:]
        data["id"] = snapshot.documentID
        do {
            return try Firestore.Decoder().decode(VendorSupply.self, from: data)
        } catch {
            throw AppError.unknown("Document \(snapshot.reference.path) illisible : \(error.localizedDescription)")
        }
    }

    private static func appError(from error: any Error) -> AppError {
        FirestoreGroupOrderRepository.appError(from: error)
    }
}
#endif
