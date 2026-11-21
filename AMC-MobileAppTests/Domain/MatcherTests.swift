import Foundation
import Testing
@testable import AMC_MobileApp

/// S-09 : rapprochement des envies des familles et des disponibilités des vendeurs.
struct MatcherTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 86_400
    static let geohashes = ["g-sm": "f25dv", "g-ho": "f25ej", "g-far": "f2m6x"]

    static func wish(
        _ group: String = "g-sm", _ household: String = "h1", _ quantity: Double = 10,
        category: Product.Category = .grains, unit: MeasureUnit = .kilogram, product: String? = nil,
        from: Double? = nil, until: Double? = nil
    ) -> GroupWish {
        GroupWish(id: "w-\(group)-\(household)-\(category.rawValue)", groupId: group, householdId: household,
                  category: category, productId: product, quantity: quantity, unit: unit, frequency: .monthly,
                  wantedFrom: from.map { start.addingTimeInterval($0 * day) },
                  wantedUntil: until.map { start.addingTimeInterval($0 * day) },
                  createdAt: start, updatedAt: start)
    }

    static func supply(
        _ id: String, _ quantity: Double = 100, vendor: String = "v1", category: Product.Category = .grains,
        unit: MeasureUnit = .kilogram, product: String? = nil, zones: [String] = ["f25d"],
        from: Double = 0, to: Double = 30
    ) -> VendorSupply {
        VendorSupply(id: id, vendorId: vendor, category: category, productId: product, quantity: quantity, unit: unit,
                     availableFrom: start.addingTimeInterval(from * day), availableTo: start.addingTimeInterval(to * day),
                     servedZones: zones, createdAt: start, updatedAt: start)
    }

    static func matches(_ wishes: [GroupWish], _ supplies: [VendorSupply]) -> [Matcher.Match] {
        Matcher.matches(wishes: wishes, groupGeohashes: geohashes, supplies: supplies)
    }

    // MARK: Aucun match

    @Test func noMatchWhenNothingOverlaps() {
        #expect(Self.matches([], []).isEmpty)
        #expect(Self.matches([Self.wish()], []).isEmpty)
        #expect(Self.matches([], [Self.supply("s1")]).isEmpty)
        // Autre catégorie, autre unité, autre produit.
        #expect(Self.matches([Self.wish(category: .eggs)], [Self.supply("s1", category: .grains)]).isEmpty)
        #expect(Self.matches([Self.wish(unit: .liter)], [Self.supply("s1", unit: .kilogram)]).isEmpty)
        #expect(Self.matches([Self.wish(product: "riz")], [Self.supply("s1", product: "orge")]).isEmpty)
    }

    @Test func ignoresGroupsWithUnknownZone() {
        #expect(Self.matches([Self.wish("g-inconnu")], [Self.supply("s1", zones: ["f"])]).isEmpty)
    }

    // MARK: Plusieurs groupes

    @Test func ranksSeveralGroupsByVolume() {
        let wishes = [
            Self.wish("g-sm", "h1", 10), Self.wish("g-sm", "h2", 15),
            Self.wish("g-ho", "h3", 40),
        ]
        let result = Self.matches(wishes, [Self.supply("s1", zones: ["f25"])])
        #expect(result.map(\.groupId) == ["g-ho", "g-sm"])
        #expect(result.map(\.matchedQuantity) == [40, 25])
        #expect(result[1].householdCount == 2)
        #expect(result[1].lines.first?.householdCount == 2)
        #expect(result.allSatisfy { !$0.isPartial })
    }

    @Test func ranksSeveralVendorsForOneGroupAndSplitsCategories() {
        let wishes = [Self.wish("g-sm", "h1", 10), Self.wish("g-sm", "h1", 4, category: .eggs, unit: .dozen),
                      Self.wish("g-sm", "h2", 2, category: .eggs, unit: .dozen)]
        let supplies = [
            Self.supply("riz", 50, vendor: "moulins"),
            Self.supply("oeufs", 30, vendor: "ferme", category: .eggs, unit: .dozen),
            Self.supply("riz-ferme", 3, vendor: "ferme"),
        ]
        let result = Self.matches(wishes, supplies)
        #expect(result.map(\.vendorId) == ["moulins", "ferme"])
        let ferme = result[1]
        #expect(ferme.lines.map(\.category) == [.eggs, .grains])
        #expect(ferme.lines.map(\.matchedQuantity) == [6, 3])
        #expect(ferme.householdCount == 2)
        #expect(ferme.isPartial)
    }

    @Test func matchesWithTheGroupsThemselves() {
        let group = NeighborhoodGroup(id: "g-x", name: "X", neighborhood: "X", centerGeohash: "f25dv", radiusMeters: 500,
                                      coordinatorIds: [], householdCount: 1, isPublic: true, inviteCode: "X")
        let result = Matcher.matches(wishes: [Self.wish("g-x")], groups: [group], supplies: [Self.supply("s1")])
        #expect(result.map(\.id) == ["g-x|v1"])
    }

    // MARK: Hors zone

    @Test func excludesSuppliesOutOfZone() {
        let wishes = [Self.wish("g-sm", "h1"), Self.wish("g-far", "h2")]
        let result = Self.matches(wishes, [Self.supply("s1", zones: ["f25d", "f25e"])])
        #expect(result.map(\.groupId) == ["g-sm"])
        // Une zone plus fine que la cellule du groupe, ou un préfixe vide, ne compte pas.
        #expect(Self.matches([Self.wish()], [Self.supply("s1", zones: ["f25dvq", ""])]).isEmpty)
        #expect(Matcher.serves(Self.supply("s1", zones: ["F25D"]), geohash: "f25dv"))
    }

    // MARK: Quantité partielle

    @Test func partialQuantityServesWhatIsAvailable() throws {
        let wishes = [Self.wish("g-sm", "h1", 10), Self.wish("g-sm", "h2", 20)]
        let result = Self.matches(wishes, [Self.supply("s1", 8), Self.supply("s2", 12)])
        let line = try #require(result.first?.lines.first)
        #expect(line.wantedQuantity == 30)
        #expect(line.availableQuantity == 20)
        #expect(line.matchedQuantity == 20)
        #expect(line.isPartial)
        #expect(abs(line.coverage - 2.0 / 3.0) < 0.000_1)
        #expect(line.supplyIds == ["s1", "s2"])
        #expect(result.first?.isPartial == true)
    }

    @Test func fullCoverageIsPreferredAtEqualVolume() {
        let wishes = [Self.wish("g-sm", "h1", 20), Self.wish("g-ho", "h2", 10)]
        let supplies = [Self.supply("s1", 10, zones: ["f25"])]
        let result = Self.matches(wishes, supplies)
        #expect(result.map(\.groupId) == ["g-ho", "g-sm"])
        #expect(result.map(\.coverage) == [1, 0.5])
    }

    // MARK: Périodes

    @Test func excludesPeriodsThatDoNotOverlap() {
        // L'envie finit avant que la disponibilité commence.
        #expect(Self.matches([Self.wish(until: 5)], [Self.supply("s1", from: 10, to: 20)]).isEmpty)
        // L'envie commence après la fin de la disponibilité.
        #expect(Self.matches([Self.wish(from: 25)], [Self.supply("s1", from: 10, to: 20)]).isEmpty)
        // Bornes qui se touchent : chevauchement.
        #expect(Self.matches([Self.wish(until: 10)], [Self.supply("s1", from: 10, to: 20)]).count == 1)
        // Sans borne : toujours compatible.
        #expect(Self.matches([Self.wish()], [Self.supply("s1", from: 100, to: 120)]).count == 1)
    }

    @Test func onlyOverlappingWishesAndSuppliesAreCounted() throws {
        let wishes = [Self.wish("g-sm", "h1", 10, until: 5), Self.wish("g-sm", "h2", 7, from: 15)]
        let supplies = [Self.supply("tot", 50, from: 0, to: 3), Self.supply("tard", 4, from: 20, to: 40)]
        let line = try #require(Self.matches(wishes, supplies).first?.lines.first)
        #expect(line.wantedQuantity == 17)
        #expect(line.availableQuantity == 54)
        #expect(line.householdCount == 2)
    }

    // MARK: Démo

    @Test func demoDataProducesTheExpectedPairs() throws {
        let result = Matcher.matches(wishes: FakeData.demoWishes, groups: FakeData.montreal.groups,
                                     supplies: FakeData.demoSupplies)
        let ids = Set(result.map(\.id))
        let sm = FakeData.ID.saintMichel, ho = FakeData.ID.hochelaga
        #expect(ids == ["\(sm)|\(FakeData.ID.moulinsDuNord)", "\(sm)|\(FakeData.ID.fermeRive)",
                        "\(ho)|\(FakeData.ID.fermeRive)"])
        let moulins = try #require(result.first { $0.id == "\(sm)|\(FakeData.ID.moulinsDuNord)" })
        #expect(moulins.isPartial)
    }
}
