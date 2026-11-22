// GroupWishesViewModel.swift
// S-07 « Ce que le groupe veut » (T-108) : les envies de ma famille et la demande cumulée du groupe.
//
// Anonymat : l'écran ne reçoit que l'agrégat (`GroupDemand`, total et nombre de familles) et les envies
// du ménage courant ; jamais les envies d'une autre famille.
//
// Usage dans une vue :
//   @State private var model = GroupWishesViewModel(repositories: repos, groupId: id, householdId: hh)
//   .task { await model.load(); await model.observe() }

import Foundation
import Observation

@Observable @MainActor
final class GroupWishesViewModel {
    nonisolated struct Content: Sendable, Hashable {
        /// Demande du groupe, sans dire qui (familles les plus nombreuses d'abord).
        var demand: [GroupDemand]
        /// Envies de ma famille, les plus anciennes d'abord.
        var myWishes: [GroupWish]

        var isEmpty: Bool { demand.isEmpty && myWishes.isEmpty }
    }

    /// Brouillon de l'éditeur (ajout ou modification).
    nonisolated struct Draft: Sendable, Hashable {
        /// Envie modifiée ; nil pour un ajout.
        var wishId: String?
        var category: Product.Category = .produce
        var quantity: Double = 5
        var unit: MeasureUnit = .kilogram
        var frequency: GroupWish.Frequency = .weekly

        init() {}

        init(_ wish: GroupWish) {
            wishId = wish.id
            category = wish.category
            quantity = wish.quantity
            unit = wish.unit
            frequency = wish.frequency
        }

        var isNew: Bool { wishId == nil }
    }

    /// Toujours `.loaded` après le premier chargement réussi, même sans envie (l'écran propose d'en ajouter).
    private(set) var state: LoadState<Content> = .idle
    /// Vrai pendant l'écoute temps réel.
    private(set) var isLive = false
    private(set) var isSaving = false
    var actionError: AppError?

    let groupId: String
    let householdId: String
    private let repositories: AppRepositories

    init(repositories: AppRepositories, groupId: String, householdId: String) {
        self.repositories = repositories
        self.groupId = groupId
        self.householdId = householdId
    }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            apply(try await repositories.wishes.wishes(ofGroup: groupId))
        } catch {
            state = .failed(AppError(error))
        }
    }

    /// Suit les envies du groupe jusqu'à l'annulation de la tâche ; une coupure garde les données affichées.
    func observe() async {
        let stream = await repositories.wishes.observeWishes(ofGroup: groupId)
        isLive = true
        defer { isLive = false }
        do {
            for try await wishes in stream { apply(wishes) }
        } catch {
            if state.value == nil { state = .failed(AppError(error)) }
        }
    }

    /// Ajoute ou modifie une envie ; vrai si c'est enregistré.
    @discardableResult
    func save(_ draft: Draft) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            if let wishId = draft.wishId,
               var wish = state.value?.myWishes.first(where: { $0.id == wishId }) {
                wish.category = draft.category
                wish.quantity = draft.quantity
                wish.unit = draft.unit
                wish.frequency = draft.frequency
                try wish.validate()
                try await repositories.wishes.updateWish(wish)
            } else {
                let wish = GroupWish(groupId: groupId, householdId: householdId, category: draft.category,
                                     quantity: draft.quantity, unit: draft.unit, frequency: draft.frequency)
                try wish.validate()
                try await repositories.wishes.addWish(wish)
            }
            await refreshUnlessLive()
            return true
        } catch {
            actionError = AppError(error)
            return false
        }
    }

    func remove(_ wish: GroupWish) async {
        do {
            try await repositories.wishes.removeWish(id: wish.id, groupId: groupId)
            await refreshUnlessLive()
        } catch {
            actionError = AppError(error)
        }
    }

    /// Sans écoute, relit après une écriture ; avec écoute, le snapshot suffit.
    private func refreshUnlessLive() async {
        if !isLive { await load() }
    }

    private func apply(_ wishes: [GroupWish]) {
        let mine = wishes
            .filter { $0.householdId == householdId }
            .sorted { $0.createdAt < $1.createdAt }
        state = .loaded(Content(demand: GroupDemand.aggregate(wishes), myWishes: mine))
    }

    // MARK: Textes

    /// « 12 kg », « 2,5 L », « 3 douzaines ».
    nonisolated static func quantityText(_ quantity: Double, unit: MeasureUnit) -> String {
        let number = quantity.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.formattingLocale))
        switch unit {
        case .kilogram, .liter: return "\(number) \(unit.title)"
        case .dozen: return "\(number) \(FrenchPlural.word(quantity > 1 ? 2 : 1, "douzaine"))"
        case .unit: return "\(number) \(FrenchPlural.word(quantity > 1 ? 2 : 1, "unité"))"
        }
    }

    /// « 4 familles », « 1 famille ».
    nonisolated static func householdsText(_ count: Int) -> String {
        "\(count) \(FrenchPlural.word(count, "famille", plural: "familles"))"
    }
}
