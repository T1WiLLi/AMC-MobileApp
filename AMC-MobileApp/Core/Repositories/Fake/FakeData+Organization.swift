// FakeData+Organization.swift
// Jeu de démo du portail Organismes (T-116) : un organisme fictif de Saint-Michel, six groupes montréalais
// avec leur fonds de solidarité, cinq mois de financements et deux parrainages.
// Tous les noms d'organismes sont inventés.

import Foundation

nonisolated extension FakeData.ID {
    static let laRuche = "org-la-ruche"
    static let parcEx = "group-parc-ex"
    static let villeray = "group-villeray"
    static let petitePatrie = "group-petite-patrie"
    static let montrealNord = "group-montreal-nord"
}

nonisolated extension FakeData {
    private static let day: TimeInterval = 86_400

    static let demoOrganizations: [Organization] = [
        Organization(
            id: ID.laRuche, name: "Centre d'entraide La Ruche", kind: .communityCenter, neighborhood: "Saint-Michel",
            geohash: "f25dv", memberUserIds: ["user-nadia"],
            mission: "Personne ne devrait choisir entre l'épicerie et le loyer. On finance des paniers dans l'est de Montréal.",
            createdAt: Date.now.addingTimeInterval(-400 * day)
        ),
    ]

    /// Fonds du groupe : contributions et paniers déjà offerts, répartis sur les derniers mois.
    private static func fund(contributions: [Cents], applied: [(Cents, Int)], startDaysAgo: Double) -> SolidarityFund {
        var entries: [SolidarityFund.Entry] = []
        for (index, amount) in contributions.enumerated() {
            entries.append(.init(
                kind: .contribution, orderId: nil, amountCents: amount, basketCount: 0,
                date: Date.now.addingTimeInterval(-(startDaysAgo - Double(index) * 12) * day)
            ))
        }
        for (index, application) in applied.enumerated() {
            entries.append(.init(
                kind: .application, orderId: "order-demo-\(index)", amountCents: application.0,
                basketCount: application.1, date: Date.now.addingTimeInterval(-(startDaysAgo - 6 - Double(index) * 12) * day)
            ))
        }
        return SolidarityFund(entries: entries)
    }

    static let demoSolidarityProfiles: [GroupSolidarityProfile] = [
        GroupSolidarityProfile(
            groupId: ID.saintMichel, groupName: "Voisins de Saint-Michel", neighborhood: "Saint-Michel",
            centerGeohash: "f25dv", householdCount: 12, subsidizedHouseholds: 4, basketPriceCents: 2_600,
            fund: fund(contributions: [5_200, 2_600, 4_500], applied: [(5_200, 2)], startDaysAgo: 70),
            sponsorOrganizationIds: [ID.laRuche]
        ),
        GroupSolidarityProfile(
            groupId: ID.hochelaga, groupName: "Hochelaga solidaire", neighborhood: "Hochelaga",
            centerGeohash: "f25ej", householdCount: 27, subsidizedHouseholds: 9, basketPriceCents: 2_400,
            fund: fund(contributions: [4_800, 2_400], applied: [(4_800, 2)], startDaysAgo: 50),
            sponsorOrganizationIds: []
        ),
        GroupSolidarityProfile(
            groupId: ID.parcEx, groupName: "Parc-Ex Ouest", neighborhood: "Parc-Extension",
            centerGeohash: "f25dt", householdCount: 34, subsidizedHouseholds: 14, basketPriceCents: 2_600,
            fund: fund(contributions: [8_400, 5_000], applied: [(7_800, 3)], startDaysAgo: 90),
            sponsorOrganizationIds: [ID.laRuche]
        ),
        GroupSolidarityProfile(
            groupId: ID.villeray, groupName: "Villeray Nord", neighborhood: "Villeray",
            centerGeohash: "f25dw", householdCount: 19, subsidizedHouseholds: 3, basketPriceCents: 2_800,
            fund: fund(contributions: [11_200], applied: [], startDaysAgo: 30),
            sponsorOrganizationIds: []
        ),
        GroupSolidarityProfile(
            groupId: ID.petitePatrie, groupName: "Petite-Patrie en commun", neighborhood: "La Petite-Patrie",
            centerGeohash: "f25dy", householdCount: 22, subsidizedHouseholds: 0, basketPriceCents: 2_500,
            fund: fund(contributions: [2_500], applied: [], startDaysAgo: 20),
            sponsorOrganizationIds: []
        ),
        GroupSolidarityProfile(
            groupId: ID.montrealNord, groupName: "Montréal-Nord ensemble", neighborhood: "Montréal-Nord",
            centerGeohash: "f25eq", householdCount: 41, subsidizedHouseholds: 18, basketPriceCents: 2_300,
            fund: fund(contributions: [2_300], applied: [(2_300, 1)], startDaysAgo: 40),
            sponsorOrganizationIds: []
        ),
    ]

    static let demoOrganizationDonations: [OrganizationDonation] = {
        let rows: [(String, String, OrganizationDonation.Kind, Cents, Int, Int, Double)] = [
            (ID.parcEx, "Parc-Ex Ouest", .suspendedBaskets, 26_000, 10, 8, 140),
            (ID.saintMichel, "Voisins de Saint-Michel", .fund, 10_000, 3, 3, 112),
            (ID.parcEx, "Parc-Ex Ouest", .suspendedBaskets, 13_000, 5, 5, 84),
            (ID.hochelaga, "Hochelaga solidaire", .fund, 25_000, 10, 7, 61),
            (ID.saintMichel, "Voisins de Saint-Michel", .suspendedBaskets, 10_400, 4, 2, 33),
            (ID.montrealNord, "Montréal-Nord ensemble", .suspendedBaskets, 23_000, 10, 10, 12),
            (ID.parcEx, "Parc-Ex Ouest", .fund, 5_000, 1, 1, 3),
        ]
        return rows.enumerated().map { index, row in
            OrganizationDonation(
                id: "donation-demo-\(index)", organizationId: ID.laRuche, groupId: row.0, groupName: row.1,
                kind: row.2, amountCents: row.3, basketCount: row.4, householdsReached: row.5,
                date: Date.now.addingTimeInterval(-row.6 * day)
            )
        }
    }()

    static let demoSponsorships: [Sponsorship] = [
        Sponsorship(id: ID.parcEx, organizationId: ID.laRuche, groupName: "Parc-Ex Ouest",
                    neighborhood: "Parc-Extension", monthlyBasketGoal: 10, startedAt: Date.now.addingTimeInterval(-150 * day)),
        Sponsorship(id: ID.saintMichel, organizationId: ID.laRuche, groupName: "Voisins de Saint-Michel",
                    neighborhood: "Saint-Michel", monthlyBasketGoal: 5, startedAt: Date.now.addingTimeInterval(-60 * day)),
    ]
}
