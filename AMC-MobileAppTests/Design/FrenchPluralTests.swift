import Testing
@testable import AMC_MobileApp

struct FrenchPluralTests {
    @Test(arguments: [(0, false), (1, false), (2, true), (40, true), (-1, false), (-2, true)])
    func pluralRule(count: Int, expected: Bool) {
        #expect(FrenchPlural.isPlural(count) == expected)
    }

    @Test func countAgreesWithNumber() {
        #expect(FrenchPlural.count(0, "part") == "0 part")
        #expect(FrenchPlural.count(1, "part") == "1 part")
        #expect(FrenchPlural.count(24, "famille") == "24 familles")
    }

    @Test func irregularPlural() {
        #expect(FrenchPlural.count(1, "panier suspendu", plural: "paniers suspendus") == "1 panier suspendu")
        #expect(FrenchPlural.count(12, "panier suspendu", plural: "paniers suspendus") == "12 paniers suspendus")
    }

    @Test func wordOnly() {
        #expect(FrenchPlural.word(1, "engagée") == "engagée")
        #expect(FrenchPlural.word(3, "engagée") == "engagées")
    }
}
