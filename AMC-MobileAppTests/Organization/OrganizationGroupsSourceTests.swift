import Foundation
import Testing
@testable import AMC_MobileApp

/// T-208 : le portail Organismes liste les mêmes groupes que la recherche de groupes du portail Famille (mêmes
/// groupes publics, même ordre), avec leurs médias ; la carte montre les groupes et les organismes.
@MainActor
struct OrganizationGroupsSourceTests {
    private func group(_ id: String, _ name: String, geohash: String, isPublic: Bool = true) -> NeighborhoodGroup {
        NeighborhoodGroup(id: id, name: name, neighborhood: "hochelaga", centerGeohash: geohash, radiusMeters: 1_500,
                          coordinatorIds: [], householdCount: 3, isPublic: isPublic, inviteCode: "",
                          photoURL: URL(string: "grenier-media:///groups/\(id)/media/photo?v=1"))
    }

    private var organization: Organization {
        Organization(id: "org-test", name: "Organisme test", kind: .foodBank, neighborhood: "hochelaga",
                     geohash: "f25ene", memberUserIds: [], mission: "", createdAt: .now)
    }

    @Test func listsTheFamilySearchGroupsInTheSameOrder() async throws {
        let near = group("g-near", "Zèbre", geohash: "f25ene")
        let far = group("g-far", "Abeille", geohash: "f25dtg")
        let hidden = group("g-private", "Privé", geohash: "f25ene", isPublic: false)
        let groups = FakeGroupRepository(groups: [far, near, hidden])
        let repository = FakeOrganizationRepository(organizations: [organization], profiles: [], donations: [], sponsorships: [])
        let model = OrganizationPortalModel(repository: repository, groups: groups, organizationId: "org-test")
        await model.load()

        let family = try await groups.groups(inNeighborhood: nil)
        let expected = GroupsViewModel.items(publicGroups: family, householdGroups: [], neighborhood: nil,
                                             origin: Geohash.center(of: "f25ene")).map(\.id)
        #expect(model.groupsByDistance.map(\.groupId) == expected)
        #expect(model.groupsByDistance.map(\.groupId) == ["g-near", "g-far"])
        // Les médias du groupe suivent (bannière et photo des cartes).
        #expect(model.groupsByDistance.first?.group?.photoURL == near.photoURL)
        #expect(model.sponsorableGroups.count == 2)
    }

    @Test func aGroupWithoutFundCanBeFunded() async throws {
        let groups = FakeGroupRepository(groups: [group("g-new", "Nouveau", geohash: "f25ene")])
        let repository = FakeOrganizationRepository(organizations: [organization], profiles: [], donations: [], sponsorships: [])
        let model = OrganizationPortalModel(repository: repository, groups: groups, organizationId: "org-test")
        await model.load()
        #expect(await model.donate(.suspendedBaskets(count: 2), toGroup: "g-new"))
        #expect(model.profile(id: "g-new")?.basketsFundable == 2)
        #expect(model.profile(id: "g-new")?.group != nil)
    }

    @Test func mapShowsGroupsAndOrganizationsWithTheOwnOneFirst() {
        let other = OrganizationDirectoryEntry(id: "org-autre", name: "Autre", kind: .foundation,
                                               neighborhood: "verdun", geohash: "f25dtg")
        let broken = OrganizationDirectoryEntry(id: "org-x", name: "Sans position", kind: .foundation,
                                                neighborhood: "", geohash: "")
        let profile = GroupSolidarityProfile(group: group("g1", "Groupe", geohash: "f25ene"))
        let places = OrganizationPortalModel.mapPlaces(groups: [profile], directory: [other, broken],
                                                       organization: organization)
        #expect(places.map(\.id) == ["group:g1", "organization:org-test", "organization:org-autre"])
        #expect(places.filter(\.isMine).count == 1)
    }

    @Test func organizationDecodesWithoutMediaFields() throws {
        let json = #"{"id":"o1","name":"Banque","kind":"inconnu"}"#
        let decoded = try JSONDecoder().decode(Organization.self, from: Data(json.utf8))
        #expect(decoded.kind == .communityCenter)
        #expect(decoded.photoUpdatedAt == nil)
        #expect(decoded.bannerURL.absoluteString.hasSuffix("organizations/o1/media/banner"))
    }
}
