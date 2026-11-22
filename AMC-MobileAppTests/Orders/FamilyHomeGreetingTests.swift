import Testing
@testable import AMC_MobileApp

/// Salut de l'Accueil : le prénom vient du profil de la personne connectée, et la persona fake est la même partout.
@MainActor
struct FamilyHomeGreetingTests {
    @Test func firstNameIsTheFirstWordOfTheDisplayName() {
        #expect(FamilyHomeViewModel.firstName(from: "Amina Benali") == "Amina")
        #expect(FamilyHomeViewModel.firstName(from: "Jean-Philippe Roy Tremblay") == "Jean-Philippe")
        #expect(FamilyHomeViewModel.firstName(from: "Yacine") == "Yacine")
    }

    @Test func firstNameIgnoresSurroundingSpaces() {
        #expect(FamilyHomeViewModel.firstName(from: "  Nadia   Côté ") == "Nadia")
        #expect(FamilyHomeViewModel.firstName(from: "Lou\tMartin") == "Lou")
    }

    @Test func emptyDisplayNameGivesNoFirstName() {
        #expect(FamilyHomeViewModel.firstName(from: "").isEmpty)
        #expect(FamilyHomeViewModel.firstName(from: "   ").isEmpty)
    }

    @Test func homeGreetsTheSignedInProfile() async {
        let context = AppContext.instant
        let model = FamilyHomeViewModel(
            repositories: context.repositories,
            userId: context.userId,
            householdId: context.householdId,
            groupId: context.groupId ?? ""
        )
        await model.load()
        let profile = try? await context.repositories.users.user(id: context.userId)
        #expect(model.state.value?.firstName == profile.map { FamilyHomeViewModel.firstName(from: $0.displayName) })
    }

    /// Mode fake : la connexion Google fake est la persona du ménage de démo (même uid, même prénom).
    @Test func fakeSignInIsTheDemoHouseholdPersona() async throws {
        #expect(AuthUser.sample.id == AppContext.demo.userId)
        let profile = try await AppContext.instant.repositories.users.user(id: AuthUser.sample.id)
        #expect(FamilyHomeViewModel.firstName(from: AuthUser.sample.displayName)
                == FamilyHomeViewModel.firstName(from: profile.displayName))
        #expect(FamilyHomeViewModel.firstName(from: AuthUser.sample.displayName) == "Amina")
    }
}
