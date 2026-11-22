// ProductPhotoUploader.swift
// Photo d'un produit du catalogue vendeur (T-089) : téléversement et suppression.
// Le projet est sur Spark, sans Cloud Storage : la photo est un document `media` Firestore
// (`vendors/{vendorId}/media/photo-product-{productId}`, firestore.rules), comme les photos de vitrine (T-157).
// `ImageStoreProductPhotoUploader` passe par `AppRepositories.images` (Firestore en live, mémoire en fake).

import Foundation
import UIKit

/// Téléverse la photo JPEG d'un produit et renvoie son URL de téléchargement.
nonisolated protocol ProductPhotoUploader: Sendable {
    func uploadPhoto(_ jpegData: Data, vendorId: String, productId: String) async throws -> URL
    /// Supprime la photo ; sans effet si elle n'existe pas.
    func deletePhoto(vendorId: String, productId: String) async throws
}

nonisolated enum ProductPhoto {
    /// Limite de storage.rules (5 Mo).
    static let maxBytes = 5 * 1024 * 1024
    /// Plus grand côté gardé après redimensionnement.
    static let maxDimension: CGFloat = 1600

    static func storagePath(vendorId: String, productId: String) -> String {
        "vendors/\(vendorId)/\(productId).jpg"
    }

    /// Redimensionne (plus grand côté ≤ `maxDimension`) et compresse en JPEG ; nil si ce n'est pas une image.
    static func jpegData(from imageData: Data, maxDimension: CGFloat = maxDimension) -> Data? {
        guard let image = UIImage(data: imageData), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

}

/// Range la photo dans le dépôt d'images de l'app : recadrée en carré, compressée sous 300 Kio,
/// renvoie une URL `grenier-media` versionnée (à afficher avec `MediaImage`).
nonisolated struct ImageStoreProductPhotoUploader: ProductPhotoUploader {
    let images: any ImageStore

    func uploadPhoto(_ jpegData: Data, vendorId: String, productId: String) async throws -> URL {
        let path = MediaPath.productPhoto(vendorId: vendorId, productId: productId)
        let prepared = try ImageProcessing.prepare(jpegData, spec: path.spec)
        return try await images.save(prepared, at: path)
    }

    func deletePhoto(vendorId: String, productId: String) async throws {
        try await images.delete(at: .productPhoto(vendorId: vendorId, productId: productId))
    }
}

/// Téléverseur en mémoire (previews, tests, mode fake). Les URL renvoyées ne pointent nulle part :
/// l'écran garde l'aperçu local de la photo choisie.
actor FakeProductPhotoUploader: ProductPhotoUploader {
    private let behavior: FakeBehavior
    private(set) var photos: [String: Data] = [:]

    init(behavior: FakeBehavior = .instant) {
        self.behavior = behavior
    }

    func uploadPhoto(_ jpegData: Data, vendorId: String, productId: String) async throws -> URL {
        try await behavior.simulate()
        guard jpegData.count <= ProductPhoto.maxBytes else { throw AppError.permissionDenied }
        let path = ProductPhoto.storagePath(vendorId: vendorId, productId: productId)
        photos[path] = jpegData
        return URL(string: "https://storage.grenier.invalid/\(path)")!
    }

    func deletePhoto(vendorId: String, productId: String) async throws {
        try await behavior.simulate()
        photos[ProductPhoto.storagePath(vendorId: vendorId, productId: productId)] = nil
    }
}
