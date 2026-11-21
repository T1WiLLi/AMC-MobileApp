import Foundation
import Testing
@testable import AMC_MobileApp

/// T-156 : onboarding après l'inscription (préférences, quartier, ménage), puis le tableau de bord Familles.
@MainActor
struct PostSignupOnboardingTests {
    private static func newUser(householdId: String? = "household-neuf", completed: Bool? = false) -> AppUser {
        AppUser(id: "uid-neuf", displayName: "Amina Benali", photoURL: nil, language: .french, roles: [.family],
                neighborhood: "", dietaryPreferences: [], seniorMode: false, householdId: householdId,
                vendorId: nil, onboardingCompleted: completed)
    }

    private static let household = Household(id: "household-neuf", name: "Ménage de Amina", size: 1, geohash: "", userIds: ["uid-neuf"])

    private struct Fixture {
        var repositories: AppRepositories
        var users: FakeUserRepository
    }

    private static func fixture(user: AppUser = newUser(), households: [Household] = [household]) -> Fixture {
        let users = FakeUserRepository(users: [user], households: households)
        var repositories = AppRepositories.empty()
        repositories.users = users
        return Fixture(repositories: repositories, users: users)
    }

    private static func loadedModel(_ fixture: Fixture, householdId: String = "household-neuf") async -> PostSignupOnboardingViewModel {
        let model = PostSignupOnboardingViewModel(repositories: fixture.repositories, userId: "uid-neuf", householdId: householdId)
        await model.load()
        return model
    }

    // MARK: Drapeau

    @Test func onlyAnExplicitFalseNeedsOnboarding() {
        #expect(Self.newUser(completed: false).needsOnboarding)
        #expect(!Self.newUser(completed: true).needsOnboarding)
        // Profils d'avant T-156 : pas d'onboarding.
        #expect(!Self.newUser(completed: nil).needsOnboarding)
    }

    @Test func newAccountIsResolvedWithOnboardingPending() async throws {
        let users = FakeUserRepository()
        var repositories = AppRepositories.empty()
        repositories.users = users
        let context = try await AppContextResolver(repositories: repositories)
            .resolve(user: AuthUser(id: "uid-tout-neuf", displayName: "Jo Tremblay", email: "jo@example.com", photoURL: nil))
        #expect(context.needsOnboarding)
        let profile = try await users.user(id: "uid-tout-neuf")
        #expect(profile.onboardingCompleted == false)
    }

    @Test func legacyProfileIsResolvedWithoutOnboarding() async throws {
        let fixture = Self.fixture(user: Self.newUser(completed: nil))
        let context = try await AppContextResolver(repositories: fixture.repositories)
            .resolve(user: AuthUser(id: "uid-neuf", displayName: "Amina", email: "a@example.com", photoURL: nil))
        #expect(!context.needsOnboarding)
    }

    // MARK: Pré-remplissage

    @Test func loadPrefillsHouseholdNameFromDisplayName() async {
        let model = await Self.loadedModel(Self.fixture())
        #expect(model.householdName == "Ménage de Amina")
        #expect(model.householdSize == 1)
        #expect(model.step == .tastes)
    }

    @Test func defaultHouseholdName() {
        #expect(PostSignupOnboardingViewModel.defaultHouseholdName(for: "Amina Benali") == "Famille Benali")
        #expect(PostSignupOnboardingViewModel.defaultHouseholdName(for: "Jo") == "Ménage de Jo")
        #expect(PostSignupOnboardingViewModel.defaultHouseholdName(for: "") == "Mon ménage")
    }

    // MARK: Étapes

    @Test func neighborhoodIsRequiredBeforeTheHousehold() async {
        let model = await Self.loadedModel(Self.fixture())
        #expect(model.canContinue) // goûts facultatifs
        await model.next()
        #expect(model.step == .neighborhood)
        #expect(!model.canContinue)
        model.postalCode = "h2a 1b3"
        #expect(model.neighborhood?.name == "Saint-Michel")
        #expect(model.canContinue)
        await model.next()
        #expect(model.step == .household)
        model.back()
        #expect(model.step == .neighborhood)
    }

    @Test func emptyHouseholdNameBlocks() async {
        let model = await Self.loadedModel(Self.fixture())
        model.neighborhood = MontrealNeighborhood.named("Villeray")
        await model.next()
        await model.next()
        model.householdName = "   "
        #expect(model.nameError != nil)
        #expect(!model.canContinue)
        model.householdName = String(repeating: "a", count: 41)
        #expect(!model.canContinue)
    }

    @Test func progressAndStepNumbers() async {
        let model = await Self.loadedModel(Self.fixture())
        #expect(model.stepNumber == 1)
        #expect(model.stepCount == 3)
        #expect(abs(model.progress - 1.0 / 3.0) < 0.001)
        #expect(!model.canGoBack)
    }

    // MARK: Enregistrement

    @Test func finishingSavesHouseholdAndProfile() async throws {
        let fixture = Self.fixture()
        let model = await Self.loadedModel(fixture)
        model.toggle(Product.Category.eggs)
        model.toggle(Product.Category.grains)
        model.toggle(DietaryTag.halal)
        await model.next()
        model.postalCode = "H2A1B3"
        await model.next()
        model.householdName = "  Famille Benali "
        model.householdSize = 4
        await model.next()
        #expect(model.step == .done)
        #expect(model.savedHouseholdId == "household-neuf")

        let household = try await fixture.users.household(id: "household-neuf")
        #expect(household.name == "Famille Benali")
        #expect(household.size == 4)
        #expect(household.geohash == MontrealNeighborhood.named("Saint-Michel")?.geohash)
        #expect(household.userIds == ["uid-neuf"])

        let user = try await fixture.users.user(id: "uid-neuf")
        #expect(user.onboardingCompleted == true)
        #expect(user.neighborhood == "Saint-Michel")
        #expect(user.dietaryPreferences == [.halal])
        // Ordre stable de Product.Category.
        #expect(user.favoriteCategories == [.grains, .eggs])
        #expect(user.householdId == "household-neuf")
        #expect(model.tastesSummary == "Céréales et Œufs")
        #expect(model.householdSummary == "Famille Benali · 4 personnes")
    }

    @Test func accountWithoutHouseholdGetsANewOne() async throws {
        let fixture = Self.fixture(user: Self.newUser(householdId: nil), households: [])
        let model = await Self.loadedModel(fixture, householdId: "")
        model.neighborhood = MontrealNeighborhood.named("Verdun")
        await model.next()
        await model.next()
        await model.next()
        let id = try #require(model.savedHouseholdId)
        #expect(id.hasPrefix("household-"))
        let household = try await fixture.users.household(id: id)
        #expect(household.userIds == ["uid-neuf"])
        let user = try await fixture.users.user(id: "uid-neuf")
        #expect(user.householdId == id)
    }

    @Test func skipOnlyMarksOnboardingDone() async throws {
        let fixture = Self.fixture()
        let model = await Self.loadedModel(fixture)
        model.toggle(Product.Category.meat)
        #expect(await model.skip())
        let user = try await fixture.users.user(id: "uid-neuf")
        #expect(user.onboardingCompleted == true)
        #expect(user.favoriteCategories == nil)
        #expect(model.savedHouseholdId == "household-neuf")
    }

    @Test func saveFailureStaysOnHouseholdStep() async {
        var repositories = AppRepositories.empty()
        repositories.users = FailingSaveUserRepository(user: Self.newUser(), household: Self.household)
        let model = PostSignupOnboardingViewModel(repositories: repositories, userId: "uid-neuf", householdId: "household-neuf")
        await model.load()
        model.neighborhood = MontrealNeighborhood.named("Verdun")
        await model.next()
        await model.next()
        await model.next()
        #expect(model.step == .household)
        #expect(model.saveError != nil)
    }

    // MARK: Store et portail

    @Test func completingOnboardingUpdatesTheSessionContext() async {
        let store = SessionContextStore(defaults: UserDefaults(suiteName: "test-onboarding-store")!, forcesOnboarding: true)
        await store.load(for: .sample, base: .instant)
        #expect(store.context.needsOnboarding)
        store.completeOnboarding(householdId: AppContext.instant.householdId)
        #expect(!store.context.needsOnboarding)
        #expect(store.context.householdId == AppContext.instant.householdId)
    }

    @Test func finishingOpensTheFamilyPortalUnlessOnlyOthersWereChosen() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-onboarding-portal"))
        defaults.removePersistentDomain(forName: "test-onboarding-portal")
        defaults.set(Portal.vendor.rawValue, forKey: Portal.storageKey)
        defaults.set(PortalChoice.both.rawValue, forKey: OnboardingKeys.portalChoice)
        PostSignupOnboardingViewModel.openFamilyPortalIfChosen(in: defaults)
        #expect(defaults.string(forKey: Portal.storageKey) == Portal.family.rawValue)

        defaults.set(Portal.vendor.rawValue, forKey: Portal.storageKey)
        defaults.set(PortalChoice.vendor.rawValue, forKey: OnboardingKeys.portalChoice)
        PostSignupOnboardingViewModel.openFamilyPortalIfChosen(in: defaults)
        #expect(defaults.string(forKey: Portal.storageKey) == Portal.vendor.rawValue)
    }
}

/// Lit normalement, refuse toute écriture (règles, hors ligne).
private actor FailingSaveUserRepository: UserRepository {
    let user: AppUser
    let storedHousehold: Household

    init(user: AppUser, household: Household) {
        self.user = user
        self.storedHousehold = household
    }

    func user(id: String) async throws -> AppUser { user }
    func saveUser(_ user: AppUser) async throws { throw AppError.permissionDenied }
    func household(id: String) async throws -> Household { storedHousehold }
    func saveHousehold(_ household: Household) async throws { throw AppError.permissionDenied }
}
