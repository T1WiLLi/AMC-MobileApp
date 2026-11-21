import Foundation
import Testing
@testable import AMC_MobileApp

/// S-07 « Ce que le groupe veut » (T-108).
@MainActor
struct GroupWishesViewModelTests {
    private static let group = "group-test"
    private static let me = "household-moi"
    private static let neighbor = "household-voisin"

    private static func wish(_ household: String, _ category: Product.Category, _ quantity: Double,
                             _ unit: MeasureUnit = .kilogram, id: String) -> GroupWish {
        GroupWish(id: id, groupId: group, householdId: household, category: category, quantity: quantity,
                  unit: unit, frequency: .weekly, createdAt: Date(timeIntervalSince1970: Double(id.hashValue & 0xFFFF)))
    }

    private static func repositories(_ wishes: [GroupWish]) -> AppRepositories {
        var repos = AppRepositories.fake(behavior: .instant)
        repos.wishes = FakeGroupWishRepository(behavior: .instant, wishes: wishes)
        return repos
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Condition jamais remplie")
    }

    @Test func loadAggregatesTheGroupAndKeepsOnlyMyWishes() async throws {
        let repos = Self.repositories([
            Self.wish(Self.me, .produce, 5, id: "w1"),
            Self.wish(Self.neighbor, .produce, 3, id: "w2"),
            Self.wish(Self.neighbor, .eggs, 2, .dozen, id: "w3"),
        ])
        let model = GroupWishesViewModel(repositories: repos, groupId: Self.group, householdId: Self.me)
        await model.load()

        let content = try #require(model.state.value)
        #expect(content.myWishes.map(\.id) == ["w1"])
        // Anonymat : aucune envie d'une autre famille n'est exposée, seulement l'agrégat.
        #expect(!content.myWishes.contains { $0.householdId != Self.me })
        let produce = try #require(content.demand.first { $0.category == .produce })
        #expect(produce.totalQuantity == 8)
        #expect(produce.householdCount == 2)
        #expect(content.demand.contains { $0.category == .eggs && $0.unit == .dozen && $0.householdCount == 1 })
    }

    @Test func emptyGroupStillLoadsSoTheFamilyCanAddAWish() async throws {
        let model = GroupWishesViewModel(repositories: Self.repositories([]), groupId: Self.group, householdId: Self.me)
        await model.load()
        #expect(model.state.value?.isEmpty == true)
    }

    @Test func addEditAndRemoveAWish() async throws {
        let model = GroupWishesViewModel(repositories: Self.repositories([]), groupId: Self.group, householdId: Self.me)
        await model.load()

        var draft = GroupWishesViewModel.Draft()
        draft.category = .grains
        draft.quantity = 10
        #expect(await model.save(draft))
        let added = try #require(model.state.value?.myWishes.first)
        #expect(added.category == .grains && added.quantity == 10 && added.householdId == Self.me)

        var edit = GroupWishesViewModel.Draft(added)
        edit.quantity = 4
        edit.frequency = .monthly
        #expect(await model.save(edit))
        let edited = try #require(model.state.value?.myWishes.first)
        #expect(edited.id == added.id && edited.quantity == 4 && edited.frequency == .monthly)
        #expect(model.state.value?.demand.first?.totalQuantity == 4)

        await model.remove(edited)
        #expect(model.state.value?.isEmpty == true)
        #expect(model.actionError == nil)
    }

    @Test func invalidQuantityShowsAnErrorAndSavesNothing() async throws {
        let model = GroupWishesViewModel(repositories: Self.repositories([]), groupId: Self.group, householdId: Self.me)
        await model.load()
        var draft = GroupWishesViewModel.Draft()
        draft.quantity = 0
        #expect(await model.save(draft) == false)
        #expect(model.actionError != nil)
        #expect(model.state.value?.myWishes.isEmpty == true)
    }

    @Test func anotherFamilysWishUpdatesTheDemandLive() async throws {
        let repos = Self.repositories([Self.wish(Self.me, .produce, 5, id: "w1")])
        let model = GroupWishesViewModel(repositories: repos, groupId: Self.group, householdId: Self.me)
        await model.load()
        let observation = Task { await model.observe() }
        defer { observation.cancel() }
        try await waitUntil { model.isLive }
        for _ in 0..<20 { await Task.yield() }

        // Un second client (le voisin) ajoute une envie.
        try await repos.wishes.addWish(Self.wish(Self.neighbor, .produce, 7, id: ""))
        try await waitUntil { model.state.value?.demand.first?.totalQuantity == 12 }
        #expect(model.state.value?.demand.first?.householdCount == 2)
        #expect(model.state.value?.myWishes.count == 1)
    }

    @Test func quantityTexts() {
        #expect(GroupWishesViewModel.quantityText(12, unit: .kilogram) == "12 kg")
        #expect(GroupWishesViewModel.quantityText(2.5, unit: .liter) == "2,5 L")
        #expect(GroupWishesViewModel.quantityText(3, unit: .dozen) == "3 douzaines")
        #expect(GroupWishesViewModel.householdsText(1) == "1 famille")
        #expect(GroupWishesViewModel.householdsText(4) == "4 familles")
    }
}
