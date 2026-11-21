import Foundation
import Testing
@testable import AMC_MobileApp

/// T-063 : fil des lots filtrable (RQ-040, catégories RQ-039).
/// Saint-Michel (f25dv) est desservi par les pommes de terre (f25d, f25e, commande à 19 parts) et le riz (f25d) ;
/// les pommes Cortland (f25e) ne desservent que Hochelaga (f25ej).
/// Jeu étendu : des œufs bio et locaux (zone f25dv, date limite demain) et un lot de farine dont la date est passée.
@MainActor
struct OfferFeedViewModelTests {
    private typealias ID = FakeData.ID
    private static let eggs = "product-oeufs"
    private static let eggOffer = "offer-oeufs"
    private static let flour = "product-farine"
    private static let expiredOffer = "offer-farine-expiree"

    private static var extendedData: FakeData {
        var data = FakeData.montreal
        let day: TimeInterval = 86_400
        data.products += [
            Product(id: eggs, vendorId: ID.fermeRive, name: "Œufs de plein air", category: .eggs, unit: "douzaine",
                    origin: "Saint-Hyacinthe, QC", tags: [.organic, .local], photoURL: nil,
                    referenceGroceryPriceCents: 699),
            Product(id: flour, vendorId: ID.moulinsDuNord, name: "Farine tout usage", category: .flour,
                    unit: "sac de 10 kg", origin: "Québec", tags: [.vegan], photoURL: nil,
                    referenceGroceryPriceCents: 1_899),
        ]
        data.offers += [
            Offer(id: eggOffer, vendorId: ID.fermeRive, productId: eggs, totalShares: 30, shareUnit: "2 douzaines",
                  tiers: [PriceTier(minShares: 6, priceCents: 1_100)], minimumSharesToLaunch: 6,
                  deadline: .now.addingTimeInterval(day), zones: ["f25dv"], status: .active),
            Offer(id: expiredOffer, vendorId: ID.moulinsDuNord, productId: flour, totalShares: 20,
                  shareUnit: "sac de 10 kg", tiers: [PriceTier(minShares: 5, priceCents: 1_500)],
                  minimumSharesToLaunch: 5, deadline: .now.addingTimeInterval(-day), zones: ["f25d"], status: .active),
        ]
        return data
    }

    private func viewModel(
        data: FakeData = extendedData, behavior: FakeBehavior = .instant, groupId: String = ID.saintMichel
    ) -> OfferFeedViewModel {
        OfferFeedViewModel(repositories: .fake(behavior: behavior, data: data),
                           householdId: ID.aminaHousehold, groupId: groupId)
    }

    // MARK: Chargement

    @Test func listsOffersServingTheGroupByDeadline() async throws {
        let model = viewModel()
        await model.load()
        let offers = try #require(model.state.value)
        #expect(offers.map(\.id) == [Self.eggOffer, ID.potatoOffer, ID.riceOffer])
        #expect(offers.map(\.offer.deadline) == offers.map(\.offer.deadline).sorted())
        #expect(!model.hasActiveFilters)
    }

    @Test func offersAreLinkedToTheGroupOrder() async throws {
        let repos = AppRepositories.fake(behavior: .instant, data: Self.extendedData)
        try await repos.groupOrders.setShare(quantity: 2, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let model = OfferFeedViewModel(repositories: repos, householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await model.load()
        let potato = try #require(model.offers.first { $0.id == ID.potatoOffer })
        #expect(potato.committedShares == 21)
        #expect(potato.myShareQuantity == 2)
        #expect(potato.pricing.currentPriceCents == 990)
        #expect(potato.vendor.id == ID.fermeRive)
        let rice = try #require(model.offers.first { $0.id == ID.riceOffer })
        #expect(rice.groupOrder == nil)
        #expect(rice.committedShares == 0)
    }

    @Test func anotherGroupSeesItsOwnZone() async throws {
        let model = viewModel(data: .montreal, groupId: ID.hochelaga)
        await model.load()
        #expect(model.offers.map(\.id) == [ID.potatoOffer, ID.appleOffer])
        #expect(model.offers.first?.committedShares == 0)  // la commande de pommes de terre est celle de Saint-Michel
    }

    // MARK: Filtres

    @Test func availableFiltersComeFromLoadedOffers() async {
        let model = viewModel()
        #expect(model.availableCategories.isEmpty)
        await model.load()
        #expect(model.availableCategories == [.grains, .eggs, .produce])
        #expect(model.availableTags == [.organic, .halal, .vegan, .local])
        // La farine expirée ne propose pas sa catégorie.
        #expect(!model.availableCategories.contains(.flour))
    }

    @Test func filtersByCategory() async {
        let model = viewModel()
        await model.load()
        model.selectedCategory = .produce
        #expect(model.offers.map(\.id) == [ID.potatoOffer])
        #expect(model.hasActiveFilters)
        model.selectedCategory = .grains
        #expect(model.offers.map(\.id) == [ID.riceOffer])
        model.selectedCategory = .meat
        #expect(model.state == .empty)
    }

    @Test func filtersByTagsAllRequired() async {
        let model = viewModel()
        await model.load()
        model.toggle(.organic)
        #expect(model.offers.map(\.id) == [Self.eggOffer, ID.potatoOffer])
        model.toggle(.halal)
        #expect(model.selectedTags == [.organic, .halal])
        #expect(model.state == .empty)
        model.toggle(.organic)
        #expect(model.offers.map(\.id) == [ID.riceOffer])

        model.selectedCategory = .eggs
        #expect(model.state == .empty)
        model.clearFilters()
        #expect(!model.hasActiveFilters)
        #expect(model.offers.count == 3)
        // Les filtres ne changent pas ce qui est chargé.
        #expect(model.availableCategories == [.grains, .eggs, .produce])
    }

    @Test func tagTitlesAreFrench() {
        #expect(DietaryTag.allCases.map(OfferFeedViewModel.title(of:))
            == ["Bio", "Halal", "Casher", "Végétarien", "Végane", "Sans gluten", "Local"])
    }

    // MARK: États

    @Test func emptyWhenNoOfferServesTheGroup() async {
        var data = FakeData.montreal
        data.offers = []
        let model = viewModel(data: data)
        await model.load()
        #expect(model.summaries == .empty)
        #expect(model.state == .empty)
        #expect(model.availableTags.isEmpty)
    }

    @Test func failingRepositoryFails() async {
        let model = viewModel(behavior: .failing())
        await model.load()
        #expect(model.state == .failed(.offline))
        #expect(model.offers.isEmpty)
    }

    @Test func unknownGroupFails() async {
        let model = viewModel(groupId: "group-inconnu")
        await model.load()
        #expect(model.state == .failed(.notFound))
    }

    @Test func reloadKeepsOffersVisible() async {
        let model = viewModel()
        await model.load()
        model.selectedCategory = .produce
        await model.load()
        #expect(model.offers.map(\.id) == [ID.potatoOffer])
    }
}
