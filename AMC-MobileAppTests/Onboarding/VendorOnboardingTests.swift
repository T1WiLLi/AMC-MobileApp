import Foundation
import Testing
@testable import AMC_MobileApp

/// T-158 : tout compte peut ouvrir le portail Vendeurs ; sans vendeur, il passe par l'onboarding producteur.
@MainActor
struct VendorOnboardingTests {
    private static let userId = "uid-julien"

    private static func user(vendorId: String? = nil) -> AppUser {
        AppUser(id: userId, displayName: "Julien Tremblay", photoURL: nil, language: .french, roles: [.family],
                neighborhood: "Rosemont", dietaryPreferences: [], seniorMode: false, householdId: "household-julien",
                vendorId: vendorId)
    }

    private struct Fixture {
        var repositories: AppRepositories
        var users: FakeUserRepository
        var vendors: FakeVendorRepository
    }

    private static func fixture(vendors existing: [Vendor] = []) -> Fixture {
        let users = FakeUserRepository(users: [user()], households: [])
        let vendors = FakeVendorRepository(vendors: existing)
        var repositories = AppRepositories.empty()
        repositories.users = users
        repositories.vendors = vendors
        return Fixture(repositories: repositories, users: users, vendors: vendors)
    }

    /// Photothèque en mémoire : l'URL dit quelle photo c'est.
    private struct MemoryPhotoStore: VendorPhotoStoring {
        func store(_ data: Data, vendorId: String) async throws -> URL {
            URL(string: "https://example.com/\(vendorId)/\(data.count).jpg")!
        }
    }

    private static func model(_ fixture: Fixture) -> VendorOnboardingViewModel {
        VendorOnboardingViewModel(repositories: fixture.repositories, userId: userId, photoStore: MemoryPhotoStore())
    }

    private static var rosemont: MontrealNeighborhood {
        MontrealNeighborhood.all.first { $0.name.contains("Rosemont") } ?? MontrealNeighborhood.all[0]
    }

    /// Remplit les trois étapes obligatoires et avance jusqu'aux photos.
    private static func filledToPhotos(_ fixture: Fixture) async -> VendorOnboardingViewModel {
        let model = model(fixture)
        model.kind = .farm
        model.legalName = "  Ferme des Voisins "
        await model.next()
        model.productionDescription = "Légumes bio cultivés à Mirabel, cueillis la veille."
        await model.next()
        model.toggle(.produce)
        model.toggle(.eggs)
        model.toggle(rosemont)
        await model.next()
        return model
    }

    // MARK: Validation des étapes

    @Test func identityNeedsAKindAndAName() {
        typealias Rules = VendorOnboardingViewModel.Rules
        #expect(Rules.identityError(kind: nil, legalName: "Ferme") != nil)
        #expect(Rules.identityError(kind: .farm, legalName: "   ") != nil)
        #expect(Rules.identityError(kind: .farm, legalName: "F") != nil)
        #expect(Rules.identityError(kind: .farm, legalName: String(repeating: "a", count: 121)) != nil)
        #expect(Rules.identityError(kind: .bakery, legalName: "Boulangerie Lune") == nil)
    }

    @Test func productionNeedsAtLeastTwentyCharacters() {
        typealias Rules = VendorOnboardingViewModel.Rules
        #expect(Rules.productionError("Des carottes.") != nil)
        #expect(Rules.productionError("   " + String(repeating: "a", count: 19) + "   ") != nil)
        #expect(Rules.productionError("Légumes bio cultivés à Mirabel.") == nil)
        #expect(Rules.productionError(String(repeating: "a", count: 2_001)) != nil)
    }

    @Test func reachNeedsACategoryAndAZone() {
        typealias Rules = VendorOnboardingViewModel.Rules
        #expect(Rules.reachError(categories: [], zones: ["f25d"]) != nil)
        #expect(Rules.reachError(categories: [.eggs], zones: []) != nil)
        #expect(Rules.reachError(categories: [.eggs], zones: ["f25d"]) == nil)
    }

    @Test func cannotContinueUntilTheStepIsValid() async {
        let model = Self.model(Self.fixture())
        #expect(!model.canContinue)
        await model.next()
        #expect(model.step == .identity)
        model.kind = .cooperative
        model.legalName = "Coop du Marché"
        #expect(model.canContinue)
        await model.next()
        #expect(model.step == .production)
        #expect(model.canGoBack)
        model.back()
        #expect(model.step == .identity)
        #expect(!model.canGoBack)
    }

    @Test func photosAndProductAreOptional() async {
        let model = await Self.filledToPhotos(Self.fixture())
        #expect(model.step == .photos)
        #expect(model.canContinue)
        await model.next()
        #expect(model.step == .product)
        #expect(!model.hasProductDraft)
        #expect(model.canContinue)
    }

    @Test func aStartedProductMustBeValid() async {
        let model = await Self.filledToPhotos(Self.fixture())
        await model.next()
        model.product.name = "Carottes"
        #expect(model.hasProductDraft)
        #expect(!model.canContinue)
        model.product.unit = "sac de 5 kg"
        model.product.origin = "Mirabel, QC"
        model.product.referencePriceText = "8,99"
        #expect(model.canContinue)
    }

    @Test func neighborhoodsBecomeDeduplicatedZones() {
        let model = Self.model(Self.fixture())
        model.toggle(Self.rosemont)
        model.toggle(Self.rosemont)
        #expect(model.neighborhoods.isEmpty)
        model.toggle(Self.rosemont)
        #expect(model.zones == [VendorProfileViewModel.zone(for: Self.rosemont)])
        #expect(!model.neighborhoodSuggestions.contains(Self.rosemont))
    }

    // MARK: Flux complet

    @Test func finishingCreatesAnUnverifiedVendorOwnedByTheAccount() async throws {
        let fixture = Self.fixture()
        let model = await Self.filledToPhotos(fixture)
        #expect(await model.addPhoto(data: Data([1, 2, 3])))
        await model.next() // photos → produit
        await model.next() // produit vide → création
        #expect(model.step == .done)
        #expect(model.saveError == nil)

        let vendor = try await fixture.vendors.vendor(id: "vendor-\(Self.userId)")
        #expect(vendor.legalName == "Ferme des Voisins")
        #expect(vendor.kind == .farm)
        #expect(vendor.ownerId == Self.userId)
        #expect(!vendor.isVerified)
        #expect(vendor.averageRating == nil)
        #expect(vendor.productCategories == [.eggs, .produce])
        #expect(vendor.servedZones == [VendorProfileViewModel.zone(for: Self.rosemont)])
        // La photo part au stockage final seulement une fois le vendeur créé (l'aperçu, lui, est local).
        #expect(vendor.photoURLs.map(\.host) == ["example.com"])
        let previewsAreLocal = model.photoURLs.allSatisfy(\.isFileURL)
        #expect(previewsAreLocal)

        let profile = try await fixture.users.user(id: Self.userId)
        #expect(profile.vendorId == vendor.id)
        #expect(profile.roles.contains(.vendor))
        #expect(profile.roles.contains(.family))
        #expect(model.savedProduct == nil)
    }

    @Test func photosWaitForTheVendorToExist() async throws {
        let fixture = Self.fixture()
        let model = await Self.filledToPhotos(fixture)
        #expect(await model.addPhoto(data: Data([1, 2, 3])))
        // Rien n'est encore écrit côté vendeur : les règles refuseraient tant que le compte n'est pas rattaché.
        await #expect(throws: AppError.notFound) { _ = try await fixture.vendors.vendor(id: model.vendorId) }
        #expect(model.photoURLs.count == 1)
        model.removePhoto(try #require(model.photoURLs.first))
        await model.next()
        await model.next()
        #expect(try await fixture.vendors.vendor(id: model.vendorId).photoURLs.isEmpty)
    }

    // MARK: Photos (multi-sélection)

    /// Sources de photos distinctes : la taille des données dit quelle photo c'est.
    private static func sources(_ sizes: [Int]) -> [VendorOnboardingViewModel.PhotoSource] {
        sizes.map { size in { Data(repeating: 7, count: size) } }
    }

    @Test func severalPhotosAreAddedAtOnceInOrder() async throws {
        let fixture = Self.fixture()
        let model = await Self.filledToPhotos(fixture)
        #expect(model.remainingPhotoSlots == VendorOnboardingViewModel.Rules.maxPhotos)
        #expect(await model.addPhotos(Self.sources([11, 22, 33])) == 3)
        #expect(model.photoURLs.count == 3)
        #expect(model.remainingPhotoSlots == VendorOnboardingViewModel.Rules.maxPhotos - 3)
        #expect(model.photoError == nil)
        #expect(!model.isAddingPhoto)
        #expect(model.loadingPhotoCount == 0)
        #expect(model.photosSummary == FrenchPlural.count(3, "photo"))

        await model.next()
        await model.next()
        // L'ordre du choix est gardé jusqu'au vendeur : la première photo est la couverture.
        let vendor = try await fixture.vendors.vendor(id: model.vendorId)
        #expect(vendor.photoURLs.map(\.lastPathComponent) == ["11.jpg", "22.jpg", "33.jpg"])
    }

    @Test func newPhotosGoAfterTheCover() async throws {
        let fixture = Self.fixture()
        let model = await Self.filledToPhotos(fixture)
        #expect(await model.addPhoto(data: Data(repeating: 1, count: 5)))
        let cover = try #require(model.photoURLs.first)
        #expect(await model.addPhotos(Self.sources([6, 8])) == 2)
        #expect(model.photoURLs.first == cover)
        #expect(model.photoURLs.count == 3)

        await model.next()
        await model.next()
        let vendor = try await fixture.vendors.vendor(id: model.vendorId)
        #expect(vendor.photoURLs.map(\.lastPathComponent) == ["5.jpg", "6.jpg", "8.jpg"])
    }

    @Test func aSelectionStopsAtThePhotoLimit() async {
        let model = await Self.filledToPhotos(Self.fixture())
        let max = VendorOnboardingViewModel.Rules.maxPhotos
        #expect(await model.addPhotos(Self.sources(Array(1...(max - 2)))) == max - 2)
        #expect(model.remainingPhotoSlots == 2)
        // Trois choisies pour deux places : les deux premières sont gardées, et on le dit.
        #expect(await model.addPhotos(Self.sources([101, 102, 103])) == 2)
        #expect(model.photoURLs.count == max)
        #expect(model.remainingPhotoSlots == 0)
        #expect(!model.canAddPhoto)
        #expect(model.photoError != nil)
        // Plus aucune place.
        #expect(await model.addPhotos(Self.sources([200])) == 0)
        #expect(model.photoURLs.count == max)
    }

    @Test func unreadablePhotosAreSkipped() async {
        let model = await Self.filledToPhotos(Self.fixture())
        let sources: [VendorOnboardingViewModel.PhotoSource] = [{ Data([1, 2]) }, { nil }, { Data() }, { Data([3]) }]
        #expect(await model.addPhotos(sources) == 2)
        #expect(model.photoURLs.count == 2)
        #expect(model.photoError != nil)
        #expect(await model.addPhotos([]) == 0)
    }

    @Test func finishingWithAProductPublishesIt() async throws {
        let fixture = Self.fixture()
        let model = await Self.filledToPhotos(fixture)
        await model.next()
        model.product.name = "Œufs de plein air"
        model.product.category = .eggs
        model.product.unit = "douzaine"
        model.product.origin = "Mirabel, QC"
        model.product.referencePriceText = "6,49"
        await model.next()
        #expect(model.step == .done)
        let products = try await fixture.vendors.products(ofVendor: "vendor-\(Self.userId)")
        #expect(products.map(\.name) == ["Œufs de plein air"])
        #expect(products.first?.referenceGroceryPriceCents == 649)
        #expect(model.savedProduct?.name == "Œufs de plein air")
    }

    @Test func retryingReusesTheAlreadyCreatedVendor() async throws {
        let fixture = Self.fixture()
        let resolver = AppContextResolver(repositories: fixture.repositories)
        let draft = Vendor(id: "", legalName: "Ferme", kind: .farm, description: "Légumes bio de Mirabel, toute l'année.",
                           photoURLs: [], servedZones: ["f25d"], averageRating: 4.9, isVerified: true)
        let first = try await resolver.createVendor(draft, forUserId: Self.userId)
        // Le compte ne peut ni se vérifier ni se noter.
        #expect(!first.isVerified)
        #expect(first.averageRating == nil)
        var renamed = draft
        renamed.legalName = "Autre nom"
        let second = try await resolver.createVendor(renamed, forUserId: Self.userId)
        #expect(second.legalName == "Ferme")
        #expect(try await fixture.vendors.vendors().count == 1)
    }

    @Test func cannotTakeOverAnotherAccountsVendor() async {
        let other = Vendor(id: "vendor-\(Self.userId)", legalName: "Pas à moi", kind: .farm, description: "x",
                           photoURLs: [], servedZones: [], averageRating: nil, isVerified: false, ownerId: "quelqu-un")
        let fixture = Self.fixture(vendors: [other])
        let model = await Self.filledToPhotos(fixture)
        await model.next()
        await model.next()
        #expect(model.step == .product)
        #expect(model.saveError == .permissionDenied)
        let profile = try? await fixture.users.user(id: Self.userId)
        #expect(profile?.vendorId == nil)
    }

    @Test func fakeRepositoryRefusesAVerifiedOrForeignVendor() async {
        let vendors = FakeVendorRepository()
        let verified = Vendor(id: "vendor-a", legalName: "A", kind: .farm, description: "", photoURLs: [], servedZones: [],
                              averageRating: nil, isVerified: true, ownerId: "a")
        await #expect(throws: AppError.permissionDenied) { _ = try await vendors.createVendor(verified) }
        var wrongId = verified
        wrongId.isVerified = false
        wrongId.id = "vendor-b"
        await #expect(throws: AppError.permissionDenied) { _ = try await vendors.createVendor(wrongId) }
    }

    // MARK: Contexte de session

    @Test func completingOpensTheVendorPortal() async {
        let store = SessionContextStore(defaults: UserDefaults(suiteName: "vendor-onboarding-tests")!,
                                        forcesVendorOnboarding: true)
        await store.load(for: AuthUser(id: FakeData.ID.amina, displayName: "Amina", email: "a@example.com", photoURL: nil),
                         base: .instant)
        #expect(!store.context.hasVendor)
        await store.completeVendorOnboarding(vendorId: "vendor-\(FakeData.ID.amina)")
        #expect(store.context.hasVendor)
        #expect(store.context.vendorId == "vendor-\(FakeData.ID.amina)")
    }
}
