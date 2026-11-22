import Foundation
import Testing
@testable import AMC_MobileApp

/// T-075 : profil famille (RQ-015, RQ-017 à RQ-020), sur `FakeData.montreal` (Amina, Famille Benali, 5 personnes).
@MainActor
struct FamilyProfileTests {
    private typealias ID = FakeData.ID

    private func householdViewModel(
        repositories: AppRepositories = .fake(behavior: .instant),
        store: any HouseholdPrivateStore = FakeHouseholdPrivateStore(),
        issuedCodes: Set<String> = []
    ) -> HouseholdProfileViewModel {
        HouseholdProfileViewModel(repositories: repositories, privateStore: store,
                                  userId: ID.amina, householdId: ID.aminaHousehold, issuedCodes: issuedCodes)
    }

    private func validCode(_ serial: Int = 427) throws -> String {
        try ReferralCode(organisation: "CB", serial: serial).description
    }

    // MARK: Code postal → quartier

    @Test func postalCodeFindsTheNeighborhood() {
        #expect(MontrealNeighborhood.lookup(postalCode: "h2a 1b3").neighborhood?.name == "Saint-Michel")
        #expect(MontrealNeighborhood.lookup(postalCode: "H3N").neighborhood?.name == "Parc-Extension")
        #expect(MontrealNeighborhood.lookup(postalCode: "") == .empty)
        #expect(MontrealNeighborhood.lookup(postalCode: "H2") == .incomplete)
        #expect(MontrealNeighborhood.lookup(postalCode: "22A 1B3") == .invalid)
        #expect(MontrealNeighborhood.lookup(postalCode: "H2A 1B3 4") == .invalid)
        #expect(MontrealNeighborhood.lookup(postalCode: "G1R 4P5") == .notServed)
        #expect(MontrealNeighborhood.formatted(postalCode: "h2a1b3") == "H2A 1B3")
    }

    @Test func neighborhoodGeohashIsCoarse() throws {
        let saintMichel = try #require(MontrealNeighborhood.named("saint-michel"))
        #expect(saintMichel.geohash.count == 5)
        // Montréal est dans la cellule « f2 » ; 5 caractères ≈ 5 km : jamais l'adresse.
        #expect(saintMichel.geohash.hasPrefix("f2"))
    }

    // MARK: Ménage (RQ-015)

    @Test func loadsAminaHousehold() async throws {
        let viewModel = householdViewModel()
        await viewModel.load()
        #expect(viewModel.state.value?.id == ID.aminaHousehold)
        #expect(viewModel.name == "Famille Benali")
        #expect(viewModel.size == 5)
        #expect(viewModel.neighborhood?.name == "Saint-Michel")
        #expect(!viewModel.hasChanges)
        #expect(!viewModel.canSave)
        #expect(!viewModel.isSubsidized)
    }

    @Test func savesNameSizeAndNeighborhoodFromPostalCode() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let viewModel = householdViewModel(repositories: repositories)
        await viewModel.load()

        viewModel.name = "  Famille Benali-Haddad "
        viewModel.size = 6
        viewModel.postalCode = "H3N 2K4"
        #expect(viewModel.neighborhood?.name == "Parc-Extension")
        #expect(viewModel.postalMessage == "Quartier trouvé : Parc-Extension.")
        #expect(viewModel.canSave)

        await viewModel.save()
        #expect(viewModel.saveCount == 1)
        #expect(viewModel.saveError == nil)
        #expect(!viewModel.hasChanges)

        let household = try await repositories.users.household(id: ID.aminaHousehold)
        #expect(household.name == "Famille Benali-Haddad")
        #expect(household.size == 6)
        #expect(household.geohash == MontrealNeighborhood.named("Parc-Extension")?.geohash)
        let user = try await repositories.users.user(id: ID.amina)
        #expect(user.neighborhood == "Parc-Extension")
    }

    @Test func refusesAnEmptyName() async {
        let viewModel = householdViewModel()
        await viewModel.load()
        viewModel.name = "   "
        #expect(viewModel.nameError != nil)
        #expect(!viewModel.canSave)
        await viewModel.save()
        #expect(viewModel.saveCount == 0)
    }

    @Test func unservedPostalCodeKeepsTheNeighborhood() async {
        let viewModel = householdViewModel()
        await viewModel.load()
        viewModel.postalCode = "G1R 4P5"
        #expect(viewModel.neighborhood?.name == "Saint-Michel")
        #expect(viewModel.postalLookup == .notServed)
    }

    @Test func loadFailureShowsTheError() async {
        let viewModel = householdViewModel(repositories: .fake(behavior: .failing(.offline)))
        await viewModel.load()
        #expect(viewModel.state.error == .offline)
    }

    // MARK: Statut subventionné (RQ-020)

    @Test func redeemingAValidCodeStoresThePrivateProfile() async throws {
        let store = FakeHouseholdPrivateStore()
        let viewModel = householdViewModel(store: store)
        await viewModel.load()

        viewModel.codeInput = try validCode().lowercased()
        await viewModel.redeemCode()

        #expect(viewModel.isSubsidized)
        #expect(viewModel.codeError == nil)
        #expect(viewModel.codeInput.isEmpty)
        #expect(viewModel.redeemCount == 1)
        let stored = try await store.privateProfile(householdId: ID.aminaHousehold)
        #expect(stored == HouseholdPrivate(isSubsidized: true, referralCode: try validCode()))
    }

    @Test func subsidyNeverTouchesTheSharedHousehold() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let before = try await repositories.users.household(id: ID.aminaHousehold)
        let viewModel = householdViewModel(repositories: repositories)
        await viewModel.load()
        viewModel.codeInput = try validCode()
        await viewModel.redeemCode()
        #expect(try await repositories.users.household(id: ID.aminaHousehold) == before)
    }

    @Test func typoInCodeShowsAMessage() async throws {
        let store = FakeHouseholdPrivateStore()
        let viewModel = householdViewModel(store: store)
        await viewModel.load()

        var code = try validCode()
        let last = code.removeLast()
        code.append(last == "0" ? "1" : "0")
        viewModel.codeInput = code
        await viewModel.redeemCode()

        #expect(!viewModel.isSubsidized)
        #expect(viewModel.codeError?.contains("faute de frappe") == true)
        #expect(try await store.privateProfile(householdId: ID.aminaHousehold) == nil)

        viewModel.codeInput = "ORG"
        #expect(viewModel.codeError == nil)
    }

    @Test func unknownCodeIsRefusedWhenCodesAreIssued() async throws {
        let viewModel = householdViewModel(issuedCodes: [try validCode(1)])
        await viewModel.load()
        viewModel.codeInput = try validCode(2)
        await viewModel.redeemCode()
        #expect(!viewModel.isSubsidized)
        #expect(viewModel.codeError?.contains("pas reconnu") == true)
    }

    @Test func withdrawingClearsTheStatus() async throws {
        let store = FakeHouseholdPrivateStore(profiles: [
            ID.aminaHousehold: HouseholdPrivate(isSubsidized: true, referralCode: try validCode()),
        ])
        let viewModel = householdViewModel(store: store)
        await viewModel.load()
        #expect(viewModel.isSubsidized)

        await viewModel.withdrawSubsidy()
        #expect(!viewModel.isSubsidized)
        #expect(try await store.privateProfile(householdId: ID.aminaHousehold)?.isSubsidized == false)
    }

    // MARK: Préférences (RQ-017 à RQ-019)

    @Test func togglesDietaryTagsInStableOrder() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let viewModel = PreferencesViewModel(repositories: repositories, userId: ID.amina)
        await viewModel.load()
        #expect(viewModel.isSelected(.halal))
        #expect(viewModel.dietarySummary == "Halal")

        await viewModel.toggle(.glutenFree)
        await viewModel.toggle(.organic)
        #expect(viewModel.user?.dietaryPreferences == [.organic, .halal, .glutenFree])
        await viewModel.toggle(.halal)
        #expect(viewModel.user?.dietaryPreferences == [.organic, .glutenFree])
        #expect(viewModel.saveCount == 3)

        let saved = try await repositories.users.user(id: ID.amina)
        #expect(saved.dietaryPreferences == [.organic, .glutenFree])
    }

    @Test func savesLanguage() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let viewModel = PreferencesViewModel(repositories: repositories, userId: ID.amina)
        await viewModel.load()

        await viewModel.setLanguage(.english)
        // Même valeur : rien n'est réécrit.
        await viewModel.setLanguage(.english)
        #expect(viewModel.saveCount == 1)

        let saved = try await repositories.users.user(id: ID.amina)
        #expect(saved.language == .english)
    }

    @Test func everyTagHasAGroup() {
        let grouped = PreferencesViewModel.TagGroup.allCases.flatMap(\.tags)
        #expect(Set(grouped) == Set(DietaryTag.allCases))
        #expect(grouped.count == DietaryTag.allCases.count)
    }

    @Test func preferencesLoadFailure() async {
        let viewModel = PreferencesViewModel(repositories: .fake(behavior: .failing(.offline)), userId: ID.amina)
        await viewModel.load()
        #expect(viewModel.state.error == .offline)
        await viewModel.toggle(.vegan)
        #expect(viewModel.saveCount == 0)
    }
}
