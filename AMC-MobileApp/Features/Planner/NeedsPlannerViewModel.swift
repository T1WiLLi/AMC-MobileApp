// NeedsPlannerViewModel.swift
// Planificateur de besoins mensuels (T-105, RQ-099, RQ-100) : besoins et budget du ménage, stockés en local,
// et lots actifs du groupe classés par `NeedsPlanner.suggestions`.
//
//     @State private var model = NeedsPlannerViewModel(repositories: repos, householdId: id, groupId: groupId)
//     .task { await model.load() }
//     model.addNeed(.category(.grains), quantity: 10, unit: .kilograms) ; model.removeNeeds(at:)
//     Slider(value: $model.budgetDollars, in: NeedsPlannerViewModel.budgetRange, step: 5)
//     model.result : suggestions, budget utilisé, économie ; recalculé à chaque changement.

import Foundation
import Observation

@Observable
@MainActor
final class NeedsPlannerViewModel {
    /// Bornes du Slider de budget, en dollars.
    static let budgetRange: ClosedRange<Double> = 0...600

    /// Plan du mois ; chaque changement est enregistré tout de suite.
    private(set) var plan: MonthlyNeedsPlan {
        didSet { store.save(plan, forHousehold: householdId) }
    }

    /// Lots du groupe et leurs produits.
    private(set) var catalog: LoadState<Catalog> = .idle

    nonisolated struct Catalog: Sendable, Equatable {
        var offers: [Offer]
        var products: [Product]
        /// Parts déjà engagées par le groupe, par id de lot.
        var committedShares: [String: Int]
    }

    let householdId: String
    let groupId: String?
    private let repositories: AppRepositories
    private let store: any NeedsPlanStore
    private let now: @Sendable () -> Date

    init(
        repositories: AppRepositories,
        householdId: String,
        groupId: String?,
        store: any NeedsPlanStore = UserDefaultsNeedsPlanStore(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repositories = repositories
        self.householdId = householdId
        self.groupId = groupId
        self.store = store
        self.now = now
        self.plan = store.plan(forHousehold: householdId) ?? .starter
    }

    // MARK: Lecture

    var needs: [NeedItem] { plan.needs }

    /// Budget en dollars, lié au Slider (arrondi au dollar).
    var budgetDollars: Double {
        get { Double(plan.budgetCents) / 100 }
        set { plan.budgetCents = Int((min(max(newValue, Self.budgetRange.lowerBound), Self.budgetRange.upperBound)).rounded()) * 100 }
    }

    var budgetCents: Cents { plan.budgetCents }

    /// Suggestions et totaux pour le plan courant ; vide tant que les lots ne sont pas chargés.
    var result: NeedsPlanResult {
        guard let catalog = catalog.value else { return .empty }
        return NeedsPlanner.suggestions(
            offers: catalog.offers, products: catalog.products, plan: plan,
            committedShares: catalog.committedShares, now: now()
        )
    }

    /// Produits connus, pour choisir un besoin précis, par nom.
    var products: [Product] {
        (catalog.value?.products ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func coverage(of need: NeedItem) -> Double { result.coverage[need.id] ?? 0 }

    func isUnmatched(_ need: NeedItem) -> Bool { result.unmatchedNeedIds.contains(need.id) }

    func need(id: UUID) -> NeedItem? { plan.needs.first { $0.id == id } }

    // MARK: Actions

    /// Charge les lots actifs qui desservent le groupe (tous les lots actifs sans groupe).
    func load() async {
        if catalog.value == nil { catalog = .loading }
        let repositories = repositories, groupId = groupId, date = now()
        catalog = await LoadState<Catalog>.run {
            var offers = try await repositories.offers.activeOffers(inZone: nil).filter { $0.deadline > date }
            var committed: [String: Int] = [:]
            if let groupId {
                let group = try await repositories.groups.group(id: groupId)
                offers = offers.filter { OfferSummaryLoader.offer($0, serves: group) }
                for order in try await repositories.groupOrders.groupOrders(ofGroup: groupId)
                where OfferSummaryLoader.isActive(order) {
                    committed[order.offerId] = order.committedShares
                }
            }
            var products: [Product] = []
            for productId in Set(offers.map(\.productId)).sorted() {
                products.append(try await repositories.vendors.product(id: productId))
            }
            return Catalog(offers: offers, products: products, committedShares: committed)
        }
    }

    /// Ajoute un besoin ; une quantité nulle ou négative est ignorée.
    func addNeed(_ target: NeedItem.Target, quantity: Double, unit: NeedUnit) {
        guard quantity > 0 else { return }
        plan.needs.append(NeedItem(target: target, quantity: quantity, unit: unit))
    }

    func removeNeed(id: UUID) {
        plan.needs.removeAll { $0.id == id }
    }

    func removeNeeds(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where plan.needs.indices.contains(index) {
            plan.needs.remove(at: index)
        }
    }

    func setBudget(cents: Cents) {
        plan.budgetCents = max(0, cents)
    }
}
