import Foundation
import Testing
@testable import AMC_MobileApp

/// Contexte de la personne connectée (S-03, T-127) : tout vient des dépôts, jamais d'id de démo en dur.
@MainActor
struct AppContextResolverTests {
    // MARK: Données (mêmes formes que le seed : users/{uid}.householdId, vendorId, adhésions)

    private static func user(_ id: String, household: String? = nil, vendor: String? = nil,
                             roles: [AppUser.Role] = [.family]) -> AppUser {
        AppUser(id: id, displayName: id, photoURL: nil, language: .french, roles: roles, neighborhood: "parc-extension",
                dietaryPreferences: [], seniorMode: false, householdId: household, vendorId: vendor)
    }

    private static func group(_ id: String, name: String) -> NeighborhoodGroup {
        var group = FakeData.montreal.groups[0]
        group.id = id
        group.name = name
        return group
    }

    private static func member(_ householdId: String) -> GroupMember {
        GroupMember(householdId: householdId, role: .member, joinedAt: .now)
    }

    private struct Fixture {
        var repositories: AppRepositories
        var users: FakeUserRepository
    }

    /// Amina (famille, membre de deux groupes), Ferme Lafleur (vendeur seul), Jean (ménage sans groupe).
    private static func fixture() -> Fixture {
        let users = FakeUserRepository(users: [
            user("user-amina", household: "household-amina"),
            user("user-ferme-lafleur", vendor: "vendor-ferme-lafleur", roles: [.vendor]),
            user("user-jean", household: "household-jean", roles: [.host]),
        ])
        let groups = FakeGroupRepository(
            groups: [group("group-rosemont", name: "Rosemont en commun"), group("group-parc-extension", name: "Voisins de Parc-Ex")],
            members: [
                "group-parc-extension": [member("household-amina")],
                "group-rosemont": [member("household-amina")],
            ]
        )
        var repositories = AppRepositories.empty()
        repositories.users = users
        repositories.groups = groups
        return Fixture(repositories: repositories, users: users)
    }

    private static func authUser(_ id: String, name: String = "Nouvelle Voisine", email: String = "voisine@example.com") -> AuthUser {
        AuthUser(id: id, displayName: name, email: email, photoURL: nil)
    }

    // MARK: Résolution

    @Test func familyPersonaGetsHouseholdAndPrimaryGroup() async throws {
        let context = try await AppContextResolver(repositories: Self.fixture().repositories)
            .resolve(user: Self.authUser("user-amina"))
        #expect(context.isResolved)
        #expect(context.userId == "user-amina")
        #expect(context.householdId == "household-amina")
        // Groupes triés par nom : « Rosemont… » avant « Voisins… ».
        #expect(context.groupId == "group-rosemont")
        #expect(!context.hasVendor)
    }

    @Test func preferredGroupWinsWhenStillAMember() async throws {
        let resolver = AppContextResolver(repositories: Self.fixture().repositories)
        let context = try await resolver.resolve(user: Self.authUser("user-amina"), preferredGroupId: "group-parc-extension")
        #expect(context.groupId == "group-parc-extension")
        let stale = try await resolver.resolve(user: Self.authUser("user-amina"), preferredGroupId: "group-quitte")
        #expect(stale.groupId == "group-rosemont")
    }

    @Test func vendorPersonaGetsVendorWithoutHousehold() async throws {
        let context = try await AppContextResolver(repositories: Self.fixture().repositories)
            .resolve(user: Self.authUser("user-ferme-lafleur"))
        #expect(context.vendorId == "vendor-ferme-lafleur")
        #expect(context.hasVendor)
        #expect(!context.hasHousehold)
        #expect(context.groupId == nil)
    }

    @Test func householdWithoutGroupHasNoGroup() async throws {
        let context = try await AppContextResolver(repositories: Self.fixture().repositories)
            .resolve(user: Self.authUser("user-jean"))
        #expect(context.householdId == "household-jean")
        #expect(!context.hasGroup)
    }

    @Test func newAccountGetsAHouseholdAndAProfileWithoutVendor() async throws {
        let fixture = Self.fixture()
        let context = try await AppContextResolver(repositories: fixture.repositories)
            .resolve(user: Self.authUser("uid-neuf", name: "  "))
        #expect(context.householdId == "household-uid-neuf")
        #expect(context.groupId == nil)
        #expect(!context.hasVendor)
        let profile = try await fixture.users.user(id: "uid-neuf")
        #expect(profile.householdId == "household-uid-neuf")
        #expect(profile.vendorId == nil)
        #expect(profile.displayName == "voisine")
        let household = try await fixture.users.household(id: "household-uid-neuf")
        #expect(household.userIds == ["uid-neuf"])
    }

    @Test func vendorCanCreateAHouseholdAndKeepsVendor() async throws {
        let fixture = Self.fixture()
        let context = try await AppContextResolver(repositories: fixture.repositories)
            .createHousehold(for: Self.authUser("user-ferme-lafleur"))
        #expect(context.householdId == "household-user-ferme-lafleur")
        #expect(context.vendorId == "vendor-ferme-lafleur")
        let profile = try await fixture.users.user(id: "user-ferme-lafleur")
        #expect(profile.roles.contains(.family))
        #expect(profile.vendorId == "vendor-ferme-lafleur")
    }

    @Test func readFailurePropagates() async {
        var repositories = AppRepositories.empty()
        repositories.users = FakeUserRepository(behavior: .failing(.offline))
        await #expect(throws: AppError.offline) {
            try await AppContextResolver(repositories: repositories).resolve(user: Self.authUser("x"))
        }
    }

    @Test func primaryGroupRule() {
        #expect(AppContextResolver.primaryGroupId(among: [], preferred: "a") == nil)
        #expect(AppContextResolver.primaryGroupId(among: ["a", "b"], preferred: nil) == "a")
        #expect(AppContextResolver.primaryGroupId(among: ["a", "b"], preferred: "b") == "b")
    }

    // MARK: Store de session

    @Test func storeResolvesThenClearsOnSignOut() async {
        let defaults = UserDefaults(suiteName: "AppContextResolverTests-\(UUID().uuidString)")!
        let store = SessionContextStore(defaults: defaults)
        #expect(!store.context.isResolved)
        let base = AppContext(repositories: Self.fixture().repositories, userId: "", householdId: "", groupId: nil,
                              vendorId: "", status: .unresolved)
        await store.load(for: Self.authUser("user-amina"), base: base)
        #expect(store.phase == .ready)
        #expect(store.context.householdId == "household-amina")
        #expect(store.householdId == "household-amina")
        store.clear()
        #expect(store.phase == .idle)
        #expect(!store.context.isResolved)
        #expect(store.householdId == nil)
    }

    @Test func storeUsesAnAlreadyResolvedBaseAsIs() async {
        let store = SessionContextStore(defaults: UserDefaults(suiteName: "AppContextResolverTests-\(UUID().uuidString)")!)
        await store.load(for: .sample, base: .instant)
        #expect(store.context.householdId == AppContext.instant.householdId)
        #expect(store.phase == .ready)
    }

    @Test func storeReportsFailure() async {
        var repositories = AppRepositories.empty()
        repositories.users = FakeUserRepository(behavior: .failing(.offline))
        let store = SessionContextStore(defaults: UserDefaults(suiteName: "AppContextResolverTests-\(UUID().uuidString)")!)
        await store.load(for: Self.authUser("x"), base: AppContext(repositories: repositories, userId: "", householdId: "",
                                                                    groupId: nil, vendorId: "", status: .unresolved))
        #expect(store.phase == .failed(.offline))
        #expect(!store.context.isResolved)
    }

    @Test func unresolvedContextHasNoDemoIds() {
        let context = AppContext.unresolved
        #expect(!context.isResolved)
        #expect(context.userId.isEmpty && context.householdId.isEmpty && context.vendorId.isEmpty)
        #expect(context.groupId == nil)
    }
}
