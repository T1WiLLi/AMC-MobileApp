import Testing
@testable import AMC_MobileApp

struct HomeOfferFilterTests {
    @Test func countsCategoriesInCatalogOrder() {
        let result = HomeOfferFilter.categoryCounts([.eggs, .grains, .eggs, .produce])
        #expect(result.map(\.category) == [.grains, .eggs, .produce])
        #expect(result.map(\.count) == [1, 2, 1])
    }

    @Test func noCategoriesGivesNoChips() {
        #expect(HomeOfferFilter.categoryCounts([]).isEmpty)
        #expect(!HomeOfferFilter.showsChips([]))
    }

    @Test func chipsNeedAtLeastTwoTypes() {
        #expect(!HomeOfferFilter.showsChips([.eggs, .eggs]))
        #expect(HomeOfferFilter.showsChips([.eggs, .meat]))
    }

    @Test func collapsedListShowsAtMostTheLimit() {
        #expect(HomeOfferFilter.visibleCount(total: 12, isExpanded: false) == HomeOfferFilter.collapsedLimit)
        #expect(HomeOfferFilter.visibleCount(total: 3, isExpanded: false) == 3)
        #expect(HomeOfferFilter.visibleCount(total: 12, isExpanded: true) == 12)
    }
}
