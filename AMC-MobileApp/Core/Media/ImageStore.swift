// ImageStore.swift
// Stockage des images de profil, de groupe et des bannières (T-122).
// Live : `FirestoreImageStore` (octets JPEG dans `…/media/{nom}`, gratuit sur Spark). Previews, tests et mode fake :
// `FakeImageStore` en mémoire (les données de démo, elles, pointent vers le catalogue d'assets).

import Foundation

nonisolated protocol ImageStore: Sendable {
    /// Enregistre l'image et renvoie l'URL versionnée (`grenier-media:///…?v=…`) à poser sur le document parent.
    func save(_ image: PreparedImage, at path: MediaPath) async throws -> URL
    /// Données JPEG de l'image ; `.notFound` si elle n'existe pas.
    func imageData(at path: MediaPath) async throws -> Data
    /// Supprime l'image ; sans effet si elle n'existe pas.
    func delete(at path: MediaPath) async throws
}

nonisolated enum MediaVersion {
    /// Version d'une image : millisecondes depuis 1970 (croissante, lisible dans une URL).
    static func make(_ date: Date = .now) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

/// Images en mémoire. Mêmes limites que les règles Firestore (300 Kio au plus).
actor FakeImageStore: ImageStore {
    private let behavior: FakeBehavior
    private(set) var images: [MediaPath: PreparedImage] = [:]
    private var lastVersion: Int64 = 0

    init(behavior: FakeBehavior = .instant) {
        self.behavior = behavior
    }

    func save(_ image: PreparedImage, at path: MediaPath) async throws -> URL {
        try await behavior.simulate()
        guard image.jpeg.count <= 300 * 1_024 else { throw AppError.permissionDenied }
        images[path] = image
        // Deux envois dans la même milliseconde gardent des versions distinctes.
        lastVersion = max(MediaVersion.make(), lastVersion + 1)
        return path.url(version: lastVersion)
    }

    func imageData(at path: MediaPath) async throws -> Data {
        try await behavior.simulate()
        guard let image = images[path] else { throw AppError.notFound }
        return image.jpeg
    }

    func delete(at path: MediaPath) async throws {
        try await behavior.simulate()
        images[path] = nil
    }
}
