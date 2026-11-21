// MediaReference.swift
// Images de profil, de groupe et bannières (T-122) : où elles vivent et comment on les nomme.
//
// Spark (gratuit) n'a pas Cloud Storage : une image est un JPEG compressé (octets, 300 Kio au plus) dans son
// propre petit document Firestore (règles T-132) :
//   users/{uid}/media/avatar        photo de profil (écrite par son propriétaire)
//   groups/{groupId}/media/photo    photo du groupe (écrite par un coordinateur)
//   groups/{groupId}/media/banner   bannière du groupe (écrite par un coordinateur)
//
// Le document parent garde la date d'envoi (`photoUpdatedAt` / `bannerUpdatedAt`, serverTimestamp) ; l'app en déduit
// une URL versionnée qui pointe vers ce média, sans aucune URL Storage :
//   AppUser.photoURL / NeighborhoodGroup.photoURL / bannerURL = grenier-media:///groups/g1/media/banner?v=1732200000000
// `v` change à chaque envoi : les listes savent qu'une image existe et le cache mémoire est invalidé tout seul.
// Les données fake utilisent des images du catalogue d'assets : grenier-asset:///BannerSaintMichel.

import CoreGraphics
import Foundation

/// Un document `media` (une image).
nonisolated enum MediaPath: Hashable, Sendable {
    case userAvatar(userId: String)
    case groupPhoto(groupId: String)
    case groupBanner(groupId: String)
    /// T-157 : photo de vitrine d'un vendeur (`vendors/{id}/media/photo-…`), plusieurs par vendeur.
    case vendorPhoto(vendorId: String, photoId: String)

    /// Chemin du document Firestore.
    var documentPath: String {
        switch self {
        case .userAvatar(let userId): "users/\(userId)/media/avatar"
        case .groupPhoto(let groupId): "groups/\(groupId)/media/photo"
        case .groupBanner(let groupId): "groups/\(groupId)/media/banner"
        case .vendorPhoto(let vendorId, let photoId): "vendors/\(vendorId)/media/\(photoId)"
        }
    }

    /// Format attendu pour cette image.
    var spec: ImageSpec {
        switch self {
        case .userAvatar, .groupPhoto: .square
        case .groupBanner: .banner
        case .vendorPhoto: .showcase
        }
    }

    /// Relit un chemin de document ; nil s'il ne correspond à aucun média connu.
    init?(documentPath: String) {
        let parts = documentPath.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[2] == "media", !parts[1].isEmpty else { return nil }
        switch (parts[0], parts[3]) {
        case ("users", "avatar"): self = .userAvatar(userId: parts[1])
        case ("groups", "photo"): self = .groupPhoto(groupId: parts[1])
        case ("groups", "banner"): self = .groupBanner(groupId: parts[1])
        case ("vendors", let photoId) where photoId.hasPrefix("photo-"):
            self = .vendorPhoto(vendorId: parts[1], photoId: photoId)
        default: return nil
        }
    }

    /// URL versionnée à poser sur le document parent.
    func url(version: Int64) -> URL {
        var components = URLComponents()
        components.scheme = MediaURL.mediaScheme
        components.host = ""
        components.path = "/" + documentPath
        components.queryItems = [URLQueryItem(name: "v", value: String(version))]
        return components.url!
    }
}

/// Lecture des URL d'images de l'app.
nonisolated enum MediaURL {
    static let mediaScheme = "grenier-media"
    static let assetScheme = "grenier-asset"

    enum Source: Equatable, Sendable {
        /// Document `media` Firestore (ou son équivalent fake).
        case media(MediaPath)
        /// Image du catalogue d'assets (données de démo).
        case asset(String)
        /// http(s) ou fichier local : chargé tel quel.
        case remote(URL)
    }

    static func source(of url: URL) -> Source? {
        switch url.scheme {
        case mediaScheme:
            let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
            return MediaPath(documentPath: path).map(Source.media)
        case assetScheme:
            let name = url.lastPathComponent
            return name.isEmpty || name == "/" ? nil : .asset(name)
        case "http", "https", "file":
            return .remote(url)
        default:
            return nil
        }
    }

    /// Image de démo du catalogue d'assets.
    static func asset(_ name: String) -> URL {
        URL(string: "\(assetScheme):///\(name)")!
    }

    /// Version de l'URL (`v`), nil si absente.
    static func version(of url: URL) -> Int64? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "v" }?.value
            .flatMap { Int64($0) }
    }
}

/// Taille et compression d'une image avant envoi.
nonisolated struct ImageSpec: Hashable, Sendable {
    var width: Int
    var height: Int
    /// Qualité JPEG de départ ; baisse au besoin pour tenir sous `targetBytes` et `maxBytes`.
    var quality: CGFloat
    /// Taille visée (indicative) des données JPEG.
    var targetBytes: Int
    /// Au-delà, l'image est refusée (firestore.rules : `data` en octets, 300 Kio au plus).
    var maxBytes: Int = 290_000

    /// Photo de profil et photo de groupe : 400 × 400, JPEG 0,7 (< 80 Ko visés).
    static let square = ImageSpec(width: 400, height: 400, quality: 0.7, targetBytes: 80_000)
    /// Bannière de groupe : 1200 × 450, JPEG 0,65 (< 200 Ko visés).
    static let banner = ImageSpec(width: 1_200, height: 450, quality: 0.65, targetBytes: 200_000)
    /// Photo de vitrine d'un vendeur (T-157) : 1000 × 750 (4:3), JPEG 0,65 (< 200 Ko visés).
    static let showcase = ImageSpec(width: 1_000, height: 750, quality: 0.65, targetBytes: 200_000)

    var size: CGSize { CGSize(width: width, height: height) }
    var aspectRatio: CGFloat { CGFloat(width) / CGFloat(height) }
}

/// Image prête à envoyer : JPEG recadré et compressé.
nonisolated struct PreparedImage: Hashable, Sendable {
    var jpeg: Data
    var width: Int
    var height: Int

    /// Taille une fois encodée en base64 (4 caractères pour 3 octets).
    var base64Size: Int { Self.base64Size(of: jpeg.count) }

    static func base64Size(of byteCount: Int) -> Int { (byteCount + 2) / 3 * 4 }
}
