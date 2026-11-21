// FirestoreVendorRepository.swift
// Dépôt Firestore des vendeurs (`vendors`) et de leurs produits (`products`) — B-018.
// Même comportement que `FakeVendorRepository` : mêmes tris, mêmes erreurs.
// Écritures : seul `saveProduct` écrit ; `firestore.rules` exige que l'utilisateur soit le vendeur
// du produit (`users/{uid}.vendorId`) et n'accepte que les champs de `isValidProduct`.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

nonisolated final class FirestoreVendorRepository: VendorRepository, @unchecked Sendable {
    private let db: Firestore

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    private var vendorsRef: CollectionReference { db.collection(FirestoreCollection.vendors) }
    private var productsRef: CollectionReference { db.collection(FirestoreCollection.products) }

    // MARK: - Vendeurs

    func vendors() async throws -> [Vendor] {
        try await Self.fetch(Vendor.self, vendorsRef).sorted { $0.legalName < $1.legalName }
    }

    func vendor(id: String) async throws -> Vendor {
        try await Self.fetchOne(Vendor.self, vendorsRef.document(id))
    }

    // MARK: - Produits

    func products(ofVendor vendorId: String) async throws -> [Product] {
        try await Self.fetch(Product.self, productsRef.whereField("vendorId", isEqualTo: vendorId))
            .sorted { $0.name < $1.name }
    }

    func product(id: String) async throws -> Product {
        try await Self.fetchOne(Product.self, productsRef.document(id))
    }

    func saveProduct(_ product: Product) async throws {
        // Comme le fake : un produit n'existe que chez un vendeur connu.
        _ = try await vendor(id: product.vendorId)
        do {
            try await productsRef.document(product.id).setData(try Firestore.Encoder().encode(product))
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    // MARK: - Lecture et décodage

    static func fetch<T: Decodable>(_ type: T.Type, _ query: Query) async throws -> [T] {
        do {
            return try await query.getDocuments().documents.map { try decode(T.self, $0) }
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    static func fetchOne<T: Decodable>(_ type: T.Type, _ ref: DocumentReference) async throws -> T {
        do {
            let snapshot = try await ref.getDocument()
            guard snapshot.exists else { throw AppError.notFound }
            return try decode(T.self, snapshot)
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    /// L'id du document fait foi : un document écrit sans champ `id` (seed, console) se décode quand même.
    static func decode<T: Decodable>(_ type: T.Type, _ snapshot: DocumentSnapshot) throws -> T {
        var data = snapshot.data() ?? [:]
        data["id"] = snapshot.documentID
        do {
            return try Firestore.Decoder().decode(T.self, from: data)
        } catch {
            throw AppError.unknown("Document \(snapshot.reference.path) illisible : \(error.localizedDescription)")
        }
    }
}
#endif
