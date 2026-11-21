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
            case .foodBank: "Banque alimentaire"
            case .communityCenter: "Centre communautaire"
            case .foundation: "Fondation"
            case .localBusiness: "Commerce partenaire"
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

    var id: String { groupId }

    /// Paniers que le fonds peut déjà payer.
    var basketsFundable: Int { fund.basketsFundable(unitPriceCents: basketPriceCents) }

    /// Paniers qui manquent pour couvrir chaque ménage subventionné une fois.
    var basketsMissing: Int { max(0, subsidizedHouseholds - basketsFundable) }

    var needLevel: OrganizationLedger.NeedLevel { OrganizationLedger.needLevel(for: self) }

    func isSponsored(by organizationId: String) -> Bool { sponsorOrganizationIds.contains(organizationId) }
}

extension FirestoreCollection {
    nonisolated static let organizations = "organizations"
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
