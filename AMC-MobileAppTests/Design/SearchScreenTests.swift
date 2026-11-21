import Testing
@testable import AMC_MobileApp

@MainActor
struct SearchScreenTests {
    let catalog = SearchScreen.Suggestion.catalog

    @Test func emptyQueryShowsEverySuggestion() {
        #expect(SearchScreen.filter(catalog, query: "").count == catalog.count)
        #expect(SearchScreen.filter(catalog, query: "   ").count == catalog.count)
    }

    @Test func promptExamplesAreFound() {
        // L'invite propose « Riz, farine… » : ces recherches doivent trouver quelque chose.
        #expect(SearchScreen.filter(catalog, query: "riz").map(\.name) == ["Riz basmati"])
        #expect(SearchScreen.filter(catalog, query: "FARINE").map(\.name) == ["Farine de blé"])
        #expect(SearchScreen.filter(catalog, query: "lentilles").map(\.name) == ["Lentilles corail"])
    }

    @Test func ignoresAccents() {
        #expect(SearchScreen.filter(catalog, query: "ble").map(\.name) == ["Farine de blé"])
    }

    @Test func matchesVendor() {
        #expect(SearchScreen.filter(catalog, query: "agrinord").count == 2)
    }

    @Test func nothingMatches() {
        #expect(SearchScreen.filter(catalog, query: "caviar").isEmpty)
    }
}
