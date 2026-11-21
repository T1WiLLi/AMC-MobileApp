// NeighborhoodGroup.swift
// Collection `groups` et sa sous-collection `groups/{id}/members`.
// Nommé NeighborhoodGroup pour éviter le conflit avec SwiftUI.Group.

import Foundation

nonisolated struct NeighborhoodGroup: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var name: String
    var neighborhood: String
    var centerGeohash: String
    var radiusMeters: Int
    var coordinatorIds: [String]
    var householdCount: Int
    var isPublic: Bool
    var inviteCode: String
    /// Marque du groupe (B-033) ; nil = marque par défaut (`resolvedBranding`).
    var branding: GroupBranding? = nil
    /// T-122 : photo du groupe (`grenier-media:///groups/{id}/media/photo?v=…`), nil = initiales.
    var photoURL: URL? = nil
    /// T-122 : bannière du groupe (`…/media/banner?v=…`), nil = dégradé aux couleurs de Grenier.
    var bannerURL: URL? = nil
    /// Firestore (règles T-132) : date du dernier envoi de `groups/{id}/media/photo`, posée en `serverTimestamp`.
    /// Le dépôt Firestore en déduit `photoURL` (`resolvingMediaURLs()`).
    var photoUpdatedAt: Date? = nil
    /// Idem pour `groups/{id}/media/banner`.
    var bannerUpdatedAt: Date? = nil

    /// URL versionnées déduites des dates d'envoi Firestore (le cache des images suit la version).
    func resolvingMediaURLs() -> NeighborhoodGroup {
        var group = self
        if let date = photoUpdatedAt {
            group.photoURL = MediaPath.groupPhoto(groupId: id).url(version: MediaVersion.make(date))
        }
        if let date = bannerUpdatedAt {
            group.bannerURL = MediaPath.groupBanner(groupId: id).url(version: MediaVersion.make(date))
        }
        return group
    }

    /// Champ de date d'envoi Firestore d'une image.
    static func updatedAtField(_ kind: GroupImageKind) -> String {
        switch kind {
        case .photo: "photoUpdatedAt"
        case .banner: "bannerUpdatedAt"
        }
    }
}

/// Les deux images d'un groupe (T-122).
nonisolated enum GroupImageKind: String, Codable, Sendable, CaseIterable, Hashable {
    case photo
    case banner

    /// Champ du document `groups/{id}`.
    var field: String {
        switch self {
        case .photo: "photoURL"
        case .banner: "bannerURL"
        }
    }

    func mediaPath(groupId: String) -> MediaPath {
        switch self {
        case .photo: .groupPhoto(groupId: groupId)
        case .banner: .groupBanner(groupId: groupId)
        }
    }

    func url(in group: NeighborhoodGroup) -> URL? {
        switch self {
        case .photo: group.photoURL
        case .banner: group.bannerURL
        }
    }
}

/// Document `groups/{groupId}/members/{householdId}`.
nonisolated struct GroupMember: Identifiable, Codable, Sendable, Hashable {
    enum Role: String, Codable, Sendable, CaseIterable {
        case member
        case coordinator
    }

    var householdId: String
    var role: Role
    var joinedAt: Date

    var id: String { householdId }
}
