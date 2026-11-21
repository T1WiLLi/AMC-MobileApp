// FirestoreImageStore.swift
// Images JPEG dans Firestore (T-122, règles T-132) : Cloud Storage exige le forfait Blaze, Firestore reste gratuit.
// Un document par image, bien sous la limite de 1 Mo :
//   { data: <octets JPEG, 300 Kio au plus>, contentType: "image/jpeg", width, height, updatedAt: horodatage serveur }
// firestore.rules : `users/{uid}/media/avatar` écrit par son propriétaire ; `groups/{id}/media/{photo|banner}`
// écrit par un coordinateur du groupe ; lecture par tout utilisateur connecté ; contentType image/jpeg.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

nonisolated final class FirestoreImageStore: ImageStore, @unchecked Sendable {
    private let db: Firestore

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func save(_ image: PreparedImage, at path: MediaPath) async throws -> URL {
        guard image.jpeg.count <= 300 * 1_024 else {
            throw AppError.invalidInput("Cette image est trop lourde, même compressée. Essaie une autre photo.")
        }
        do {
            try await db.document(path.documentPath).setData([
                "data": image.jpeg, // type bytes de Firestore
                "contentType": "image/jpeg",
                "width": image.width,
                "height": image.height,
                // Les règles exigent `updatedAt == request.time`.
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
        return path.url(version: MediaVersion.make())
    }

    func imageData(at path: MediaPath) async throws -> Data {
        let snapshot: DocumentSnapshot
        do {
            snapshot = try await db.document(path.documentPath).getDocument()
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
        guard snapshot.exists else { throw AppError.notFound }
        guard let data = snapshot.get("data") as? Data else {
            throw AppError.unknown("Image \(path.documentPath) illisible.")
        }
        return data
    }

    func delete(at path: MediaPath) async throws {
        do {
            try await db.document(path.documentPath).delete()
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }
}
#endif
