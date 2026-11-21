// StorageProductPhotoUploader.swift
// Photos de produits dans Firebase Storage (T-089). Même contrat que `FakeProductPhotoUploader`.
// storage.rules : `vendors/{vendorId}/{fileName}` écrit par le vendeur rattaché, image de 5 Mo maximum.

#if canImport(FirebaseStorage)
import Foundation
import FirebaseStorage

nonisolated final class StorageProductPhotoUploader: ProductPhotoUploader, @unchecked Sendable {
    private let storage: Storage

    /// À créer APRÈS `FirebaseApp.configure()` : `FirebaseSetup` a déjà pointé Storage sur l'émulateur au besoin.
    init(storage: Storage = Storage.storage()) {
        self.storage = storage
    }

    func uploadPhoto(_ jpegData: Data, vendorId: String, productId: String) async throws -> URL {
        let ref = storage.reference(withPath: ProductPhoto.storagePath(vendorId: vendorId, productId: productId))
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        do {
            _ = try await ref.putDataAsync(jpegData, metadata: metadata)
            return try await ref.downloadURL()
        } catch {
            throw Self.appError(error)
        }
    }

    func deletePhoto(vendorId: String, productId: String) async throws {
        let ref = storage.reference(withPath: ProductPhoto.storagePath(vendorId: vendorId, productId: productId))
        do {
            try await ref.delete()
        } catch {
            let appError = Self.appError(error)
            if appError != .notFound { throw appError }
        }
    }

    /// Erreurs Storage → `AppError`.
    static func appError(_ error: any Error) -> AppError {
        let nsError = error as NSError
        guard nsError.domain == StorageErrorDomain, let code = StorageErrorCode(rawValue: nsError.code) else {
            return AppError(error)
        }
        switch code {
        case .unauthenticated: return .unauthenticated
        case .unauthorized: return .permissionDenied
        case .objectNotFound: return .notFound
        case .retryLimitExceeded: return .offline
        default: return .unknown(nsError.localizedDescription)
        }
    }
}
#endif
