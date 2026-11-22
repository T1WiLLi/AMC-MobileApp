// Organization.swift
// Portail Organismes (T-116, RQ-081) : organismes qui financent des paniers suspendus, parrainent des groupes
// et suivent leur impact. Collections Firestore :
//   - `organizations/{orgId}`                         → `Organization`
//   - `organizations/{orgId}/sponsorships/{groupId}`  → `Sponsorship`
//   - `organizations/{orgId}/donations/{donationId}`  → `OrganizationDonation`
//   - `groups/{groupId}/solidarity/fund`              → `SolidarityFundDocument` (fonds du groupe, anonyme)
// Les paiements sont SIMULÉS : aucun argent réel ne circule (`OrganizationDonation.isSimulated`).

import Foundation

/// Document `organizations/{orgId}`.
nonisolated struct Organization: Identifiable, Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case foodBank
        case communityCenter
        case foundation
        case localBusiness

        var label: String {
            switch self {
            case .foodBank: String(localized: "Banque alimentaire")
            case .communityCenter: String(localized: "Centre communautaire")
            case .foundation: String(localized: "Fondation")
            case .localBusiness: String(localized: "Commerce partenaire")
            }
        }

        var systemImage: String {
            switch self {
            case .foodBank: "takeoutbag.and.cup.and.straw.fill"
            case .communityCenter: "building.2.fill"
            case .foundation: "hands.and.sparkles.fill"
            case .localBusiness: "storefront.fill"
            }
        }
    }

    var id: String
    var name: String
    var kind: Kind
    var neighborhood: String
    /// Siège de l'organisme, pour trier les groupes par distance.
    var geohash: String
    /// Comptes autorisés à agir au nom de l'organisme (firestore.rules).
    var memberUserIds: [String]
    var mission: String
    var createdAt: Date
    /// T-208 : date d'envoi de `organizations/{id}/media/logo` (photo de profil), posée par le seed ; nil = inconnue.
    var photoUpdatedAt: Date? = nil
    /// T-208 : date d'envoi de `organizations/{id}/media/banner`.
    var bannerUpdatedAt: Date? = nil

    /// Photo de profil (absente → symbole du type d'organisme).
    var photoURL: URL { OrganizationMedia.url(.organizationLogo(organizationId: id), updatedAt: photoUpdatedAt) }
    /// Bannière (absente → dégradé Grenier).
    var bannerURL: URL { OrganizationMedia.url(.organizationBanner(organizationId: id), updatedAt: bannerUpdatedAt) }
}

// MARK: - Décodage tolérant (T-208)

extension Organization {
    /// Un document écrit à la main ou par une ancienne version du seed (sans médias, sans mission) se lit quand même.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = (try? container.decodeIfPresent(Kind.self, forKey: .kind)) ?? .communityCenter
        neighborhood = try container.decodeIfPresent(String.self, forKey: .neighborhood) ?? ""
        geohash = try container.decodeIfPresent(String.self, forKey: .geohash) ?? ""
        memberUserIds = try container.decodeIfPresent([String].self, forKey: .memberUserIds) ?? []
        mission = try container.decodeIfPresent(String.self, forKey: .mission) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        photoUpdatedAt = try? container.decodeIfPresent(Date.self, forKey: .photoUpdatedAt)
        bannerUpdatedAt = try? container.decodeIfPresent(Date.self, forKey: .bannerUpdatedAt)
    }
}

/// T-208 : fiche publique d'un organisme (`organizationDirectory/{orgId}`), pour la carte du portail Organismes.
/// Rien de privé : ni membres, ni dons. Lue par les comptes d'organisme, écrite par le seed.
nonisolated struct OrganizationDirectoryEntry: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var name: String
    var kind: Organization.Kind
    var neighborhood: String
    var geohash: String
    var photoUpdatedAt: Date? = nil
    var bannerUpdatedAt: Date? = nil

    var photoURL: URL { OrganizationMedia.url(.organizationLogo(organizationId: id), updatedAt: photoUpdatedAt) }
    var bannerURL: URL { OrganizationMedia.url(.organizationBanner(organizationId: id), updatedAt: bannerUpdatedAt) }

    init(id: String, name: String, kind: Organization.Kind, neighborhood: String, geohash: String,
         photoUpdatedAt: Date? = nil, bannerUpdatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.neighborhood = neighborhood
        self.geohash = geohash
        self.photoUpdatedAt = photoUpdatedAt
        self.bannerUpdatedAt = bannerUpdatedAt
    }

    init(_ organization: Organization) {
        self.init(id: organization.id, name: organization.name, kind: organization.kind,
                  neighborhood: organization.neighborhood, geohash: organization.geohash,
                  photoUpdatedAt: organization.photoUpdatedAt, bannerUpdatedAt: organization.bannerUpdatedAt)
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = (try? container.decodeIfPresent(Organization.Kind.self, forKey: .kind)) ?? .communityCenter
        neighborhood = try container.decodeIfPresent(String.self, forKey: .neighborhood) ?? ""
        geohash = try container.decodeIfPresent(String.self, forKey: .geohash) ?? ""
        photoUpdatedAt = try? container.decodeIfPresent(Date.self, forKey: .photoUpdatedAt)
        bannerUpdatedAt = try? container.decodeIfPresent(Date.self, forKey: .bannerUpdatedAt)
    }
}

/// URL des images d'un organisme : versionnée par la date d'envoi si on la connaît, sinon sans version (l'image
/// est tentée, son absence montre le repli).
nonisolated enum OrganizationMedia {
    static func url(_ path: MediaPath, updatedAt: Date?) -> URL {
        updatedAt.map { path.url(version: MediaVersion.make($0)) } ?? path.url
    }
}

/// Ce qu'un organisme veut financer pour un groupe.
nonisolated enum DonationRequest: Sendable, Hashable {
    /// Don libre versé dans le fonds de solidarité du groupe.
    case fund(amountCents: Cents)
    /// N paniers suspendus, au prix d'une part du groupe.
    case suspendedBaskets(count: Int)
}

/// Document `organizations/{orgId}/donations/{donationId}` : trace d'un financement simulé.
/// Ne contient aucun identifiant de ménage : l'organisme voit des totaux, jamais qui a été aidé.
nonisolated struct OrganizationDonation: Identifiable, Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case fund
        case suspendedBaskets
    }

    var id: String
    var organizationId: String
    var groupId: String
    var groupName: String
    var kind: Kind
    var amountCents: Cents
    /// Paniers entiers que ce montant paie au prix d'une part du groupe.
    var basketCount: Int
    /// Ménages subventionnés du groupe que ces paniers couvrent (au plus `basketCount`).
    var householdsReached: Int
    var date: Date
    /// Toujours vrai : Grenier ne prélève pas d'argent réel (démo).
    var isSimulated: Bool = true
}

/// Document `organizations/{orgId}/sponsorships/{groupId}` : l'organisme parraine un groupe.
nonisolated struct Sponsorship: Identifiable, Codable, Sendable, Hashable {
    /// Id du groupe parrainé (un parrainage par groupe et par organisme).
    var id: String
    var organizationId: String
    var groupName: String
    var neighborhood: String
    /// Objectif mensuel de paniers suspendus que l'organisme s'engage à financer.
    var monthlyBasketGoal: Int
    var startedAt: Date

    var groupId: String { id }

    /// Longueur maximale du quartier d'un parrainage (firestore.rules, `isValidSponsorship`).
    static let maxNeighborhoodLength = 60

    /// T-202 : un groupe accepte un quartier de 80 caractères, un parrainage 60 ; sans troncature, parrainer un
    /// groupe au long nom de quartier était refusé par les règles.
    static func storedNeighborhood(_ neighborhood: String) -> String {
        String(neighborhood.prefix(maxNeighborhoodLength))
    }
}

/// Document `groups/{groupId}/solidarity/fund` : fonds de solidarité du groupe et besoin anonyme.
nonisolated struct SolidarityFundDocument: Codable, Sendable, Equatable {
    var entries: [SolidarityFund.Entry]
    /// Nombre de ménages subventionnés (codes d'organisme validés), jamais leurs identifiants.
    var subsidizedHouseholds: Int
    /// Prix d'une part de référence (un « panier »), en cents.
    var basketPriceCents: Cents
    /// Organismes qui parrainent ce groupe.
    var sponsorOrganizationIds: [String]

    /// Prix d'un panier quand le groupe n'en a pas encore fixé : 26 $.
    static let defaultBasketPriceCents: Cents = 2_600

    init(
        entries: [SolidarityFund.Entry] = [],
        subsidizedHouseholds: Int = 0,
        basketPriceCents: Cents = SolidarityFundDocument.defaultBasketPriceCents,
        sponsorOrganizationIds: [String] = []
    ) {
        self.entries = entries
        self.subsidizedHouseholds = subsidizedHouseholds
        self.basketPriceCents = basketPriceCents
        self.sponsorOrganizationIds = sponsorOrganizationIds
    }

    var fund: SolidarityFund { SolidarityFund(entries: entries) }

    // Champs absents (document écrit à la main, seed) : valeurs par défaut plutôt qu'un échec de décodage.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([SolidarityFund.Entry].self, forKey: .entries) ?? []
        subsidizedHouseholds = try container.decodeIfPresent(Int.self, forKey: .subsidizedHouseholds) ?? 0
        basketPriceCents = try container.decodeIfPresent(Cents.self, forKey: .basketPriceCents)
            ?? Self.defaultBasketPriceCents
        sponsorOrganizationIds = try container.decodeIfPresent([String].self, forKey: .sponsorOrganizationIds) ?? []
    }
}

/// Vue d'un groupe pour un organisme : identité publique, fonds et besoin anonyme.
nonisolated struct GroupSolidarityProfile: Identifiable, Sendable, Equatable {
    var groupId: String
    var groupName: String
    var neighborhood: String
    var centerGeohash: String
    var householdCount: Int
    var subsidizedHouseholds: Int
    var basketPriceCents: Cents
    var fund: SolidarityFund
    var sponsorOrganizationIds: [String]
    /// T-208 : le groupe tel que la recherche de groupes du portail Famille le montre (photo, bannière, marque),
    /// pour réutiliser ses cartes et sa fiche publique. nil dans les anciennes données fake.
    var group: NeighborhoodGroup? = nil

    var id: String { groupId }

    /// T-208 : profil d'un groupe sans fonds (aucun don ni ménage subventionné encore).
    init(group: NeighborhoodGroup, fund: SolidarityFundDocument = SolidarityFundDocument()) {
        self.init(
            groupId: group.id, groupName: group.name, neighborhood: group.neighborhood,
            centerGeohash: group.centerGeohash, householdCount: group.householdCount,
            subsidizedHouseholds: fund.subsidizedHouseholds, basketPriceCents: fund.basketPriceCents,
            fund: fund.fund, sponsorOrganizationIds: fund.sponsorOrganizationIds, group: group
        )
    }

    init(groupId: String, groupName: String, neighborhood: String, centerGeohash: String, householdCount: Int,
         subsidizedHouseholds: Int, basketPriceCents: Cents, fund: SolidarityFund, sponsorOrganizationIds: [String],
         group: NeighborhoodGroup? = nil) {
        self.groupId = groupId
        self.groupName = groupName
        self.neighborhood = neighborhood
        self.centerGeohash = centerGeohash
        self.householdCount = householdCount
        self.subsidizedHouseholds = subsidizedHouseholds
        self.basketPriceCents = basketPriceCents
        self.fund = fund
        self.sponsorOrganizationIds = sponsorOrganizationIds
        self.group = group
    }

    /// Paniers que le fonds peut déjà payer.
    var basketsFundable: Int { fund.basketsFundable(unitPriceCents: basketPriceCents) }

    /// Paniers qui manquent pour couvrir chaque ménage subventionné une fois.
    var basketsMissing: Int { max(0, subsidizedHouseholds - basketsFundable) }

    var needLevel: OrganizationLedger.NeedLevel { OrganizationLedger.needLevel(for: self) }

    func isSponsored(by organizationId: String) -> Bool { sponsorOrganizationIds.contains(organizationId) }
}

extension FirestoreCollection {
    nonisolated static let organizations = "organizations"
    /// T-208 : fiches publiques des organismes (`OrganizationDirectoryEntry`).
    nonisolated static let organizationDirectory = "organizationDirectory"
    nonisolated static func sponsorships(ofOrganization organizationId: String) -> String {
        "organizations/\(organizationId)/sponsorships"
    }
    nonisolated static func donations(ofOrganization organizationId: String) -> String {
        "organizations/\(organizationId)/donations"
    }
    nonisolated static func solidarity(ofGroup groupId: String) -> String { "groups/\(groupId)/solidarity" }
    /// Id du seul document de `groups/{id}/solidarity`.
    nonisolated static let solidarityFundDocumentId = "fund"
}
