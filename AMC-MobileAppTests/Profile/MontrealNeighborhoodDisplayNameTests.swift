import Testing
@testable import AMC_MobileApp

/// FB-12 : le quartier d'un groupe s'affichait en slug (« cote-des-neiges », « hochelaga »).
struct MontrealNeighborhoodDisplayNameTests {
    @Test(arguments: [
        ("cote-des-neiges", "Côte-des-Neiges"),
        ("hochelaga", "Hochelaga"),
        ("notre-dame-de-grace", "Notre-Dame-de-Grâce"),
        ("mile-end", "Mile End"),
        ("plateau-mont-royal", "Plateau-Mont-Royal"),
        ("Saint-Michel", "Saint-Michel"),
        ("  villeray ", "Villeray"),
    ])
    func knownSlugsGiveTheReadableName(raw: String, expected: String) {
        #expect(MontrealNeighborhood.displayName(for: raw) == expected)
    }

    @Test func unknownSlugIsCapitalizedButSmallWordsStayLowercase() {
        #expect(MontrealNeighborhood.displayName(for: "riviere-des-prairies") == "Riviere-des-Prairies")
        #expect(MontrealNeighborhood.displayName(for: "saint-leonard") == "Saint-Leonard")
    }

    @Test func readableUnknownNameIsKept() {
        #expect(MontrealNeighborhood.displayName(for: "Le Sud-Ouest") == "Le Sud-Ouest")
        #expect(MontrealNeighborhood.displayName(for: "") == "")
    }

    @Test func slugFoldsAccentsAndSpaces() {
        #expect(MontrealNeighborhood.slug(of: "Notre-Dame-de-Grâce") == "notre-dame-de-grace")
        #expect(MontrealNeighborhood.slug(of: "Mile End") == "mile-end")
    }
}
