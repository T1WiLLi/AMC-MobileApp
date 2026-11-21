import Foundation
import Testing
@testable import AMC_MobileApp

/// T-105 : planificateur de besoins (RQ-099, RQ-100) sur `FakeData.montreal`.
/// Saint-Michel est desservi par les pommes de terre (commande à 19 parts) et le riz ; aucune légumineuse.
/// Plan de départ : 20 kg de fruits et légumes, 10 kg de céréales, 4 kg de légumineuses, 150 $.
@MainActor
struct NeedsPlannerViewModelTests {
    private typealias ID = FakeData.ID

    private func makeViewModel(
        behavior: FakeBehavior = .instant,
        store: InMemoryNeedsPlanStore = InMemoryNeedsPlanStore(),
        groupId: String? = ID.saintMichel
    ) -> NeedsPlannerViewModel {
        NeedsPlannerViewModel(repositories: .fake(behavior: behavior), householdId: ID.aminaHousehold,
                              groupId: groupId, store: store)
    }

    @Test func startsWithStarterPlanAndEmptyResult() {
        let viewModel = makeViewModel()
        #expect(viewModel.needs.count == 3)
        #expect(viewModel.budgetCents == 15_000)
        #expect(viewModel.result == .empty)
    }

    @Test func loadSuggestsGroupLotsRankedWithTierPrices() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()

        let result = viewModel.result
        #expect(result.suggestions.map(\.id) == [ID.potatoOffer, ID.riceOffer])
        let potatoes = try #require(result.suggestions.first)
        // 19 parts déjà engagées + 2 = 21 : palier de 20 à 9,90 $.
        #expect(potatoes.shares == 2)
        #expect(potatoes.unitPriceCents == 990)
        #expect(result.suggestions[1].unitPriceCents == 2_300)
        #expect(result.usedBudgetCents == 1_980 + 2_300)
        #expect(result.savingsCents == (1_599 - 990) * 2 + (2_899 - 2_300))

        let legumes = try #require(viewModel.needs.first { $0.target == .category(.legumes) })
        #expect(viewModel.isUnmatched(legumes))
        #expect(viewModel.coverage(of: legumes) == 0)
        #expect(viewModel.products.map(\.id).contains(ID.rice))
        // Les pommes Cortland ne desservent pas Saint-Michel.
        #expect(!viewModel.products.map(\.id).contains(ID.apples))
    }

    @Test func withoutGroupAllActiveLotsAreCandidates() async {
        let viewModel = makeViewModel(groupId: nil)
        await viewModel.load()
        #expect(viewModel.products.map(\.id).contains(ID.apples))
    }

    @Test func budgetSliderUpdatesSuggestions() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()

        viewModel.budgetDollars = 30
        #expect(viewModel.budgetCents == 3_000)
        let result = viewModel.result
        #expect(result.suggestions.map(\.fitsBudget) == [true, false])
        #expect(result.usedBudgetCents == 1_980)
        #expect(result.remainingBudgetCents == 1_020)
    }

    @Test func budgetIsRoundedAndClamped() {
        let viewModel = makeViewModel()
        viewModel.budgetDollars = 42.6
        #expect(viewModel.budgetCents == 4_300)
        viewModel.budgetDollars = 10_000
        #expect(viewModel.budgetCents == 60_000)
        viewModel.budgetDollars = -5
        #expect(viewModel.budgetCents == 0)
        viewModel.setBudget(cents: -100)
        #expect(viewModel.budgetCents == 0)
    }

    @Test func addAndRemoveNeedsArePersisted() async {
        let store = InMemoryNeedsPlanStore()
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        viewModel.addNeed(.product(id: ID.rice, name: "Riz basmati", category: .grains), quantity: 20, unit: .kilograms)
        viewModel.addNeed(.category(.eggs), quantity: 0, unit: .units) // ignoré
        #expect(viewModel.needs.count == 4)
        #expect(store.plan(forHousehold: ID.aminaHousehold)?.needs.count == 4)

        // Le besoin précis sur le riz prend le lot ; le besoin « céréales » n'a plus de lot.
        let riceNeed = viewModel.needs[3]
        #expect(viewModel.result.suggestions.first { $0.id == ID.riceOffer }?.needId == riceNeed.id)

        viewModel.removeNeed(id: riceNeed.id)
        viewModel.removeNeeds(at: IndexSet([0, 2]))
        #expect(viewModel.needs.map(\.target) == [.category(.grains)])

        let reopened = makeViewModel(store: store)
        #expect(reopened.needs.map(\.target) == [.category(.grains)])
    }

    @Test func emptyPlanLoadsWithoutSuggestions() async {
        let store = InMemoryNeedsPlanStore(plans: [ID.aminaHousehold: MonthlyNeedsPlan(needs: [], budgetCents: 5_000)])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        #expect(viewModel.needs.isEmpty)
        #expect(viewModel.result.suggestions.isEmpty)
        #expect(viewModel.catalog.value != nil)
    }

    @Test func failureIsReported() async {
        let viewModel = makeViewModel(behavior: .failing(.offline))
        await viewModel.load()
        #expect(viewModel.catalog.error == .offline)
        #expect(viewModel.result == .empty)
    }

    @Test func userDefaultsStoreRoundTrips() throws {
        let suite = "NeedsPlannerViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsNeedsPlanStore(defaults: defaults)
        #expect(store.plan(forHousehold: "h") == nil)
        store.save(.starter, forHousehold: "h")
        #expect(store.plan(forHousehold: "h") == .starter)
        #expect(store.plan(forHousehold: "other") == nil)
    }
}
