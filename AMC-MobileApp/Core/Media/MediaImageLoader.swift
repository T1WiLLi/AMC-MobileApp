// MediaImageLoader.swift
// Charge et garde en mémoire (NSCache) les images de profil, de groupe et les bannières (T-122).
// La clé est l'URL complète, version comprise : une nouvelle image (nouveau `v`) n'est jamais masquée
// par l'ancienne, et une liste qui réaffiche la même image ne relit pas Firestore.

import UIKit

@MainActor
final class MediaImageLoader {
    static let shared = MediaImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    /// Chargements en cours : deux cartes qui demandent la même image ne la lisent qu'une fois.
    private var inFlight: [URL: Task<UIImage, any Error>] = [:]

    init() {
        // ~40 bannières ou ~400 avatars décodés.
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    /// Image déjà en mémoire (affichage immédiat, sans fondu).
    func cachedImage(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        if case .asset(let name) = MediaURL.source(of: url) { return UIImage(named: name) }
        return cache.object(forKey: url as NSURL)
    }

    /// Met une image en mémoire, par exemple juste après l'avoir envoyée : elle s'affiche sans aller-retour.
    func prime(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
    }

    func image(for url: URL, store: any ImageStore) async throws -> UIImage {
        if let cached = cachedImage(for: url) { return cached }
        if let task = inFlight[url] { return try await task.value }
        guard let source = MediaURL.source(of: url) else { throw AppError.notFound }
        let task = Task<UIImage, any Error> {
            let data: Data
            switch source {
            case .asset:
                throw AppError.notFound // Asset absent du catalogue (sinon `cachedImage` l'aurait trouvé).
            case .media(let path):
                data = try await store.imageData(at: path)
            case .remote(let remote):
                data = try await URLSession.shared.data(from: remote).0
            }
            guard let image = await Self.decode(data) else {
                throw AppError.unknown("Image illisible.")
            }
            return image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let image = try await task.value
        prime(image, for: url)
        return image
    }

    /// Décodage hors du fil principal (`preparingForDisplay` évite la saccade au premier affichage).
    nonisolated private static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
    }

    private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.size.height * image.scale * image.scale * 4)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
