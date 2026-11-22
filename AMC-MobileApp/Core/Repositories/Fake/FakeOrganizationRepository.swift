// FakeOrganizationRepository.swift
// Portail Organismes (T-116) en mémoire : mêmes règles que `FirestoreOrganizationRepository`.

import Foundation

actor FakeOrganizationRepository: OrganizationRepository {
    private let behavior: FakeBehavior
    private var organizations: [String: Organization]
    private var profiles: [String: GroupSolidarityProfile]
    private var donations: [OrganizationDonation]
    private var sponsorships: [String: [Sponsorship]]
    private let now: @Sendable () -> Date

    init(
        behavior: FakeBehavior = .instant,
        organizations: [Organization] = FakeData.demoOrganizations,
        profiles: [GroupSolidarityProfile] = FakeData.demoSolidarityProfiles,
        donations: [OrganizationDonation] = FakeData.demoOrganizationDonations,
        sponsorships: [Sponsorship] = FakeData.demoSponsorships,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.behavior = behavior
        self.organizations = Dictionary(organizations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.profiles = Dictionary(profiles.map { ($0.groupId, $0) }, uniquingKeysWith: { first, _ in first })
        self.donations = donations
        self.sponsorships = Dictionary(grouping: sponsorships, by: \.organizationId)
        self.now = now
    }

    func organization(id: String) async throws -> Organization {
        try await behavior.simulate()
        guard let organization = organizations[id] else { throw AppError.notFound }
        return organization
    }

    func solidarityProfiles() async throws -> [GroupSolidarityProfile] {
        try await behavior.simulate()
        return profiles.values.sorted { $0.groupName.localizedStandardCompare($1.groupName) == .orderedAscending }
    }

    func solidarityProfile(groupId: String) async throws -> GroupSolidarityProfile {
        try await behavior.simulate()
        guard let profile = profiles[groupId] else { throw AppError.notFound }
        return profile
    }

    func donations(ofOrganization organizationId: String) async throws -> [OrganizationDonation] {
        try await behavior.simulate()
        return donations.filter { $0.organizationId == organizationId }.sorted { $0.date > $1.date }
    }

    func sponsorships(ofOrganization organizationId: String) async throws -> [Sponsorship] {
        try await behavior.simulate()
        return (sponsorships[organizationId] ?? []).sorted { $0.startedAt < $1.startedAt }
    }

    @discardableResult
    func donate(_ request: DonationRequest, toGroup groupId: String, organizationId: String) async throws -> OrganizationDonation {
        try await behavior.simulate()
        guard organizations[organizationId] != nil, var profile = profiles[groupId] else { throw AppError.notFound }
        let (donation, fund) = try OrganizationLedger.record(
            request, to: profile, organizationId: organizationId, donationId: "donation-\(UUID().uuidString)", date: now()
        )
        profile.fund = fund
        profiles[groupId] = profile
        donations.append(donation)
        return donation
    }

    @discardableResult
    func sponsor(groupId: String, organizationId: String, monthlyBasketGoal: Int) async throws -> Sponsorship {
        try await behavior.simulate()
        guard monthlyBasketGoal > 0 else { throw AppError.invalidInput("Choisis un objectif d'au moins 1 panier par mois.") }
        guard organizations[organizationId] != nil, var profile = profiles[groupId] else { throw AppError.notFound }
        var list = sponsorships[organizationId] ?? []
        if let index = list.firstIndex(where: { $0.groupId == groupId }) {
            list[index].monthlyBasketGoal = monthlyBasketGoal
            sponsorships[organizationId] = list
            return list[index]
        }
        let sponsorship = Sponsorship(
            id: groupId, organizationId: organizationId, groupName: profile.groupName,
            neighborhood: Sponsorship.storedNeighborhood(profile.neighborhood), monthlyBasketGoal: monthlyBasketGoal, startedAt: now()
        )
        list.append(sponsorship)
        sponsorships[organizationId] = list
        if !profile.sponsorOrganizationIds.contains(organizationId) {
            profile.sponsorOrganizationIds.append(organizationId)
            profiles[groupId] = profile
        }
        return sponsorship
    }

    func endSponsorship(groupId: String, organizationId: String) async throws {
        try await behavior.simulate()
        sponsorships[organizationId]?.removeAll { $0.groupId == groupId }
        profiles[groupId]?.sponsorOrganizationIds.removeAll { $0 == organizationId }
    }
}
