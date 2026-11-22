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
    /// B-056 : groupe public (listé, code fixe `inviteCode`) ou privé (jamais listé, invitations à usage
    /// unique `GroupInvitation`). Un document sans ce champ est public (décodage tolérant).
    var isPublic: Bool
    /// Code fixe d'un groupe public (RQ-026). Ne fait pas entrer dans un groupe privé : il faut une invitation.
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
    /// B-056 : utilisateur qui a créé le groupe ; nil pour les anciens documents (le premier coordonnateur).
    var createdBy: String? = nil
    /// T-174 : somme des étoiles des avis des familles (`groups/{id}/ratings`), tenue dans la même transaction
    /// que chaque avis (firestore.rules le vérifie). nil = aucun avis.
    var ratingSum: Int? = nil
    /// T-174 : nombre d'avis (un par ménage).
    var ratingCount: Int? = nil

    /// T-174 : moyenne et nombre d'avis, pour les cartes et la fiche sans relire les avis.
    var ratingSummary: RatingRules.Summary { RatingRules.summary(sum: ratingSum, count: ratingCount) }

    /// B-056 : créateur du groupe, seul à changer sa visibilité et à gérer ses invitations.
    /// Même calcul que `groupCreatorId` dans firestore.rules.
    var creatorId: String? { createdBy ?? coordinatorIds.first }

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

// MARK: - Décodage tolérant (B-056)

extension NeighborhoodGroup {
    /// Les champs absents prennent leur valeur par défaut : un groupe sans `isPublic` est public,
    /// sans `inviteCode` n'a pas de code fixe, sans `coordinatorIds` n'a pas de coordonnateur.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        neighborhood = try container.decodeIfPresent(String.self, forKey: .neighborhood) ?? ""
        centerGeohash = try container.decodeIfPresent(String.self, forKey: .centerGeohash) ?? ""
        radiusMeters = try container.decodeIfPresent(Int.self, forKey: .radiusMeters) ?? 1_500
        coordinatorIds = try container.decodeIfPresent([String].self, forKey: .coordinatorIds) ?? []
        householdCount = try container.decodeIfPresent(Int.self, forKey: .householdCount) ?? 0
        isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic) ?? true
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode) ?? ""
        branding = try container.decodeIfPresent(GroupBranding.self, forKey: .branding)
        photoURL = try container.decodeIfPresent(URL.self, forKey: .photoURL)
        bannerURL = try container.decodeIfPresent(URL.self, forKey: .bannerURL)
        photoUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .photoUpdatedAt)
        bannerUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .bannerUpdatedAt)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        ratingSum = try container.decodeIfPresent(Int.self, forKey: .ratingSum)
        ratingCount = try container.decodeIfPresent(Int.self, forKey: .ratingCount)
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

/// B-056 : invitation à usage unique d'un groupe privé, document `groupInvitations/{code}`.
/// Le créateur du groupe la crée, la partage (lien `https://grenier.app/join/<code>`), la voit et la révoque.
/// Elle sert une seule fois : la rejoindre pose `usedBy` / `usedAt` dans la même transaction que l'adhésion.
nonisolated struct GroupInvitation: Identifiable, Codable, Sendable, Hashable {
    enum Status: String, Sendable, Hashable {
        case active
        case used
        case revoked
    }

    /// Code de `GroupRules.inviteCodeLength` caractères, aussi id du document.
    var code: String
    var groupId: String
    /// Utilisateur qui l'a créée (le créateur du groupe).
    var createdBy: String
    var createdAt: Date
    /// Ménage qui l'a utilisée.
    var usedBy: String? = nil
    var usedAt: Date? = nil
    var revokedAt: Date? = nil

    var id: String { code }

    var status: Status {
        if usedBy != nil { return .used }
        if revokedAt != nil { return .revoked }
        return .active
    }

    /// Lien à partager (`https://grenier.app/join/<code>`).
    var shareURL: URL? { GroupRules.shareableInviteLink(for: code) }
    /// Lien encodé dans le QR de l'invitation (B-058) : `grenier://join/<code>`, ouvert par l'app.
    var appURL: URL? { GroupRules.appInviteLink(for: code) }
}
