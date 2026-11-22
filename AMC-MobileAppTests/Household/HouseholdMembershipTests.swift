import Foundation
import Testing
@testable import AMC_MobileApp

/// T-159 : plusieurs comptes dans un ménage (adresse, demande, acceptation, retrait).
@MainActor
struct HouseholdMembershipTests {
    // MARK: Adresse

    @Test func addressKeyIgnoresCaseAccentsSpacesAndAbbreviations() {
        let a = HouseholdAddress(streetNumber: "1234", street: "Rue St-Édouard", postalCode: "h2r 1a1")
        let b = HouseholdAddress(streetNumber: " 1234 ", street: "saint edouard", postalCode: "H2R1A1")
        #expect(a.key == "1234saintedouard-h2r1a1")
        #expect(a.key == b.key)
        #expect(a.lookupId == b.lookupId)
    }

    @Test func avenueAndBoulevardAbbreviationsMatch() {
        let short = HouseholdAddress(streetNumber: "55", street: "av. du Parc", postalCode: "H2V 4E7")
        let long = HouseholdAddress(streetNumber: "55", street: "Avenue du Parc", postalCode: "h2v4e7")
        #expect(short.key == long.key)
        #expect(HouseholdAddress(streetNumber: "8", street: "boul. Saint-Laurent", postalCode: "H2X 2T1").key
            == HouseholdAddress(streetNumber: "8", street: "Boulevard St-Laurent", postalCode: "H2X2T1").key)
    }

    @Test func differentNumberOrApartmentLetterIsAnotherAddress() {
        let base = HouseholdAddress(streetNumber: "1234", street: "Jarry Est", postalCode: "H2R 1A1")
        #expect(base.key != HouseholdAddress(streetNumber: "1236", street: "Jarry Est", postalCode: "H2R 1A1").key)
        #expect(base.key != HouseholdAddress(streetNumber: "1234A", street: "Jarry Est", postalCode: "H2R 1A1").key)
        #expect(base.key != HouseholdAddress(streetNumber: "1234", street: "Jarry Ouest", postalCode: "H2R 1A1").key)
    }

    @Test func incompleteAddressHasNoKey() {
        #expect(HouseholdAddress(streetNumber: "", street: "Jarry", postalCode: "H2R 1A1").key == nil)
        #expect(HouseholdAddress(streetNumber: "12", street: "  ", postalCode: "H2R 1A1").key == nil)
        #expect(HouseholdAddress(streetNumber: "12", street: "Jarry", postalCode: "H2R").key == nil)
        #expect(HouseholdAddress(streetNumber: "douze", street: "Jarry", postalCode: "H2R 1A1").key == nil)
    }

    @Test func lookupIdIsSha256HexOfTheKeyNeverTheAddress() throws {
        let id = try #require(HouseholdAddress(streetNumber: "1234", street: "Jarry Est", postalCode: "H2R 1A1").lookupId)
        #expect(id.count == 64)
        #expect(id.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(!id.contains("jarry"))
        // SHA-256 connu de « abc ».
        #expect(HouseholdAddress.lookupId(forKey: "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: Règles pures

    private static let household = Household(id: "household-amina", name: "Famille Benali", size: 4, geohash: "f25du",
                                             userIds: ["amina"], ownerId: "amina", memberNames: ["amina": "Amina Benali"])

    private static func request(_ userId: String = "karim", status: HouseholdJoinRequest.Status = .pending) -> HouseholdJoinRequest {
        HouseholdJoinRequest(householdId: "household-amina", userId: userId, displayName: "Karim Benali",
                             createdAt: Date(timeIntervalSince1970: 1_000), status: status)
    }

    @Test func ownerFallsBackToFirstMemberOnOldHouseholds() {
        var old = Self.household
        old.ownerId = nil
        old.userIds = ["jean", "amina"]
        #expect(HouseholdMembership.ownerId(of: old) == "jean")
        #expect(HouseholdMembership.ownerId(of: Self.household) == "amina")
    }

    @Test func ownerAcceptsAddsMemberAndName() throws {
        let updated = try HouseholdMembership.accepting(Self.request(), in: Self.household, byUserId: "amina")
        #expect(updated.userIds == ["amina", "karim"])
        #expect(updated.memberNames?["karim"] == "Karim Benali")
        #expect(HouseholdMembership.firstName(of: "karim", in: updated) == "Karim")
    }

    @Test func onlyOwnerAccepts() {
        var shared = Self.household
        shared.userIds.append("jean")
        #expect(throws: AppError.permissionDenied) {
            try HouseholdMembership.accepting(Self.request(), in: shared, byUserId: "jean")
        }
        #expect(throws: AppError.notFound) {
            try HouseholdMembership.accepting(Self.request(status: .accepted), in: Self.household, byUserId: "amina")
        }
    }

    @Test func ownerRemovesMemberMemberLeavesOwnerStays() throws {
        var shared = Self.household
        shared.userIds = ["amina", "karim", "jean"]
        shared.memberNames = ["amina": "Amina", "karim": "Karim", "jean": "Jean"]
        let removed = try HouseholdMembership.removing("karim", from: shared, byUserId: "amina")
        #expect(removed.userIds == ["amina", "jean"])
        #expect(removed.memberNames?["karim"] == nil)
        let left = try HouseholdMembership.removing("jean", from: shared, byUserId: "jean")
        #expect(left.userIds == ["amina", "karim"])
        #expect(throws: AppError.permissionDenied) { try HouseholdMembership.removing("karim", from: shared, byUserId: "jean") }
        #expect(throws: (any Error).self) { try HouseholdMembership.removing("amina", from: shared, byUserId: "amina") }
    }

    // MARK: Flux complet (dépôt fake + résolveur)

    private static func user(_ id: String, household: String?, pending: String? = nil) -> AppUser {
        AppUser(id: id, displayName: id == "karim" ? "Karim Benali" : "Amina Benali", photoURL: nil, language: .french,
                roles: [.family], neighborhood: "Villeray", dietaryPreferences: [], seniorMode: false,
                householdId: household, vendorId: nil, onboardingCompleted: true, pendingHouseholdId: pending)
    }

    private static func repositories() -> (AppRepositories, FakeUserRepository) {
        let karimOwn = Household(id: "household-karim", name: "Ménage de Karim", size: 1, geohash: "", userIds: ["karim"], ownerId: "karim")
        let users = FakeUserRepository(users: [user("amina", household: "household-amina"), user("karim", household: "household-karim")],
                                       households: [household, karimOwn])
        var repositories = AppRepositories.empty()
        repositories.users = users
        return (repositories, users)
    }

    @Test func twoAccountsAtSameAddressEndInSameHouseholdAfterAcceptance() async throws {
        let (repositories, users) = Self.repositories()
        let address = HouseholdAddress(streetNumber: "1234", street: "Jarry Est", postalCode: "H2R 1A1")
        let lookupId = try #require(address.lookupId)
        try await users.registerHouseholdAddress(HouseholdAddressEntry(id: lookupId, householdId: "household-amina",
                                                                        name: "Famille Benali", ownerId: "amina"))

        // Karim saisit la même adresse, écrite autrement : il trouve le ménage d'Amina (son nom seulement).
        let typed = HouseholdAddress(streetNumber: "1234", street: "rue jarry est", postalCode: "h2r1a1")
        let typedId = try #require(typed.lookupId)
        let match = try #require(try await users.householdAddress(lookupId: typedId))
        #expect(match.name == "Famille Benali")

        try await users.requestToJoin(Self.request())
        var karim = try await users.user(id: "karim")
        karim.pendingHouseholdId = match.householdId
        try await users.saveUser(karim)

        // Avant l'acceptation : Karim ne peut pas pointer vers le ménage, et le résolveur le laisse chez lui.
        karim.householdId = "household-amina"
        await #expect(throws: AppError.permissionDenied) { try await users.saveUser(karim) }
        let resolver = AppContextResolver(repositories: repositories)
        let waiting = try await resolver.resolve(user: AuthUser(id: "karim", displayName: "Karim Benali", email: "k@example.com", photoURL: nil))
        #expect(waiting.householdId == "household-karim")

        // Amina voit la demande et l'accepte.
        let pending = try await users.joinRequests(ofHousehold: "household-amina", byUserId: "amina")
        #expect(pending.map(\.userId) == ["karim"])
        await #expect(throws: AppError.permissionDenied) {
            try await users.joinRequests(ofHousehold: "household-amina", byUserId: "karim")
        }
        _ = try await users.acceptJoinRequest(householdId: "household-amina", userId: "karim", byUserId: "amina")

        // Au prochain rechargement, Karim arrive dans le ménage d'Amina et la demande disparaît.
        let joined = try await resolver.resolve(user: AuthUser(id: "karim", displayName: "Karim Benali", email: "k@example.com", photoURL: nil))
        #expect(joined.householdId == "household-amina")
        #expect(try await users.user(id: "karim").pendingHouseholdId == nil)
        #expect(try await users.joinRequest(householdId: "household-amina", userId: "karim") == nil)
        #expect(try await users.household(id: "household-amina").userIds == ["amina", "karim"])
    }

    @Test func declinedRequestLeavesRequesterAtHome() async throws {
        let (repositories, users) = Self.repositories()
        try await users.requestToJoin(Self.request())
        try await users.saveUser(Self.user("karim", household: "household-karim", pending: "household-amina"))
        try await users.deleteJoinRequest(householdId: "household-amina", userId: "karim")
        let context = try await AppContextResolver(repositories: repositories)
            .resolve(user: AuthUser(id: "karim", displayName: "Karim Benali", email: "k@example.com", photoURL: nil))
        #expect(context.householdId == "household-karim")
        #expect(try await users.household(id: "household-amina").userIds == ["amina"])
    }

    @Test func secondAddressRegistrationDoesNotStealTheFirst() async throws {
        let (_, users) = Self.repositories()
        let id = HouseholdAddress.lookupId(forKey: "1234jarryest-h2r1a1")
        try await users.registerHouseholdAddress(HouseholdAddressEntry(id: id, householdId: "household-amina", name: "Famille Benali", ownerId: "amina"))
        try await users.registerHouseholdAddress(HouseholdAddressEntry(id: id, householdId: "household-karim", name: "Ménage de Karim", ownerId: "karim"))
        #expect(try await users.householdAddress(lookupId: id)?.householdId == "household-amina")
    }

    @Test func removedMemberFallsBackToOwnHousehold() async throws {
        let (repositories, users) = Self.repositories()
        try await users.requestToJoin(Self.request())
        _ = try await users.acceptJoinRequest(householdId: "household-amina", userId: "karim", byUserId: "amina")
        try await users.saveUser(Self.user("karim", household: "household-amina"))
        _ = try await users.removeMember("karim", fromHousehold: "household-amina", byUserId: "amina")
        // Le fake renvoie le ménage ; Firestore refuserait la lecture. Dans les deux cas Karim n'en est plus membre.
        let context = try await AppContextResolver(repositories: repositories)
            .resolve(user: AuthUser(id: "karim", displayName: "Karim Benali", email: "k@example.com", photoURL: nil))
        #expect(context.householdId == "household-karim")
    }

    // MARK: Onboarding : rejoindre ou créer

    /// Karim, compte tout neuf, avec le ménage créé à l'inscription ; Amina a inscrit son ménage au 1234 Jarry Est.
    private static func onboardingFixture() async throws -> (PostSignupOnboardingViewModel, FakeUserRepository) {
        var karim = user("karim", household: "household-karim")
        karim.onboardingCompleted = false
        karim.neighborhood = ""
        let karimOwn = Household(id: "household-karim", name: "Ménage de Karim", size: 1, geohash: "", userIds: ["karim"], ownerId: "karim")
        let lookupId = try #require(HouseholdAddress(streetNumber: "1234", street: "Jarry Est", postalCode: "H2R 1A1").lookupId)
        let users = FakeUserRepository(
            users: [user("amina", household: "household-amina"), karim],
            households: [household, karimOwn],
            addresses: [HouseholdAddressEntry(id: lookupId, householdId: "household-amina", name: "Famille Benali", ownerId: "amina")]
        )
        var repositories = AppRepositories.empty()
        repositories.users = users
        let model = PostSignupOnboardingViewModel(repositories: repositories, userId: "karim", householdId: "household-karim")
        await model.load()
        await model.next()                       // goûts → quartier
        model.postalCode = "H2R 1A1"
        model.neighborhood = MontrealNeighborhood.all.first
        await model.next()                       // quartier → ménage
        model.streetNumber = "1234"
        model.street = "rue Jarry est"
        return (model, users)
    }

    @Test func sameAddressOffersToJoinThenWaitsForOwner() async throws {
        let (model, users) = try await Self.onboardingFixture()
        await model.next()
        #expect(model.step == .joinChoice)
        #expect(model.matchName == "Famille Benali")

        await model.next()                       // « Rejoindre Famille Benali »
        #expect(model.step == .waiting)
        #expect(try await users.user(id: "karim").pendingHouseholdId == "household-amina")
        #expect(try await users.user(id: "karim").householdId == "household-karim")
        #expect(try await users.joinRequests(ofHousehold: "household-amina", byUserId: "amina").count == 1)

        await model.checkJoin()
        #expect(model.step == .waiting)          // pas encore acceptée

        _ = try await users.acceptJoinRequest(householdId: "household-amina", userId: "karim", byUserId: "amina")
        await model.checkJoin()
        #expect(model.step == .done)
        #expect(model.savedHouseholdId == "household-amina")
        let karim = try await users.user(id: "karim")
        #expect(karim.householdId == "household-amina")
        #expect(karim.onboardingCompleted == true)
        #expect(karim.pendingHouseholdId == nil)
    }

    @Test func declinedRequestLetsRequesterCreateOwnHousehold() async throws {
        let (model, users) = try await Self.onboardingFixture()
        await model.next()
        await model.next()
        try await users.deleteJoinRequest(householdId: "household-amina", userId: "karim")   // Amina refuse
        await model.checkJoin()
        #expect(model.joinDeclined)
        await model.next()                       // « Créer mon ménage »
        #expect(model.step == .done)
        let karim = try await users.user(id: "karim")
        #expect(karim.householdId == "household-karim")
        #expect(karim.pendingHouseholdId == nil)
        #expect(try await users.household(id: "household-karim").addressKey == "1234jarryest-h2r1a1")
    }

    @Test func cancelReturnsToChoiceAndCreateInsteadKeepsFirstHouseholdFindable() async throws {
        let (model, users) = try await Self.onboardingFixture()
        await model.next()
        await model.next()
        await model.cancelJoin()
        #expect(model.step == .joinChoice)
        #expect(try await users.joinRequest(householdId: "household-amina", userId: "karim") == nil)
        #expect(await model.createOwnHousehold())
        let lookupId = try #require(model.address.lookupId)
        #expect(try await users.householdAddress(lookupId: lookupId)?.householdId == "household-amina")
        #expect(try await users.household(id: "household-karim").ownerId == "karim")
    }

    @Test func newAddressCreatesHouseholdAndRegistersIt() async throws {
        let (model, users) = try await Self.onboardingFixture()
        model.streetNumber = "88"
        await model.next()
        #expect(model.step == .done)
        let lookupId = try #require(model.address.lookupId)
        let entry = try #require(try await users.householdAddress(lookupId: lookupId))
        #expect(entry.householdId == "household-karim")
        #expect(entry.ownerId == "karim")
    }
}
