// VendorSuppliesViewModel.swift
// S-08 « Mes disponibilités » (T-109) : ce que le vendeur a à offrir, avant même de créer un lot.
//
// Usage dans une vue :
//   @State private var model = VendorSuppliesViewModel(repositories: repos, vendorId: id)
//   .task { await model.load(); await model.observe() }

import Foundation
import Observation

@Observable @MainActor
final class VendorSuppliesViewModel {
    /// Brouillon de l'éditeur (ajout ou modification).
    nonisolated struct Draft: Sendable, Hashable, Identifiable {
        var supplyId: String?
        var category: Product.Category = .produce
        var quantity: Double = 100
        var unit: MeasureUnit = .kilogram
        var availableFrom: Date
        var availableTo: Date
        var servedZones: [String]

        var id: String { supplyId ?? "nouvelle" }
        var isNew: Bool { supplyId == nil }

        init(now: Date = .now, zones: [String] = []) {
            availableFrom = Calendar.current.startOfDay(for: now)
            availableTo = availableFrom.addingTimeInterval(14 * 86_400)
            servedZones = zones
        }

        init(_ supply: VendorSupply) {
            supplyId = supply.id
            category = supply.category
            quantity = supply.quantity
            unit = supply.unit
            availableFrom = supply.availableFrom
            availableTo = supply.availableTo
            servedZones = supply.servedZones
        }
    }

    /// Disponibilités par date de début ; `.empty` si aucune.
    private(set) var state: LoadState<[VendorSupply]> = .idle
    private(set) var isLive = false
    private(set) var isSaving = false
    /// Zones desservies du vendeur, proposées par défaut à une nouvelle disponibilité.
    private(set) var vendorZones: [String] = []
    var actionError: AppError?

    let vendorId: String
    private let repositories: AppRepositories
    private let now: @Sendable () -> Date

    init(repositories: AppRepositories, vendorId: String, now: @escaping @Sendable () -> Date = { .now }) {
        self.repositories = repositories
        self.vendorId = vendorId
        self.now = now
    }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            if vendorZones.isEmpty {
                vendorZones = (try? await repositories.vendors.vendor(id: vendorId))?.servedZones ?? []
            }
            apply(try await repositories.supplies.supplies(ofVendor: vendorId))
        } catch {
            state = .failed(AppError(error))
        }
    }

    /// Suit les disponibilités jusqu'à l'annulation de la tâche ; une coupure garde les données affichées.
    func observe() async {
        let stream = await repositories.supplies.observeSupplies(ofVendor: vendorId)
        isLive = true
        defer { isLive = false }
        do {
            for try await supplies in stream { apply(supplies) }
        } catch {
            if state.value == nil { state = .failed(AppError(error)) }
        }
    }

    /// Nouveau brouillon avec les zones du vendeur.
    func newDraft() -> Draft { Draft(now: now(), zones: vendorZones) }

    /// Ajoute ou modifie une disponibilité ; vrai si c'est enregistré.
    @discardableResult
    func save(_ draft: Draft) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            if let supplyId = draft.supplyId, var supply = state.value?.first(where: { $0.id == supplyId }) {
                supply.category = draft.category
                supply.quantity = draft.quantity
                supply.unit = draft.unit
                supply.availableFrom = draft.availableFrom
                supply.availableTo = draft.availableTo
                supply.servedZones = draft.servedZones
                try supply.validate()
                try await repositories.supplies.updateSupply(supply)
            } else {
                let supply = VendorSupply(vendorId: vendorId, category: draft.category, quantity: draft.quantity,
                                          unit: draft.unit, availableFrom: draft.availableFrom,
                                          availableTo: draft.availableTo, servedZones: draft.servedZones)
                try supply.validate()
                try await repositories.supplies.addSupply(supply)
            }
            if !isLive { await load() }
            return true
        } catch {
            actionError = AppError(error)
            return false
        }
    }

    func remove(_ supply: VendorSupply) async {
        do {
            try await repositories.supplies.removeSupply(id: supply.id, vendorId: vendorId)
            if !isLive { await load() }
        } catch {
            actionError = AppError(error)
        }
    }

    /// Vrai si la disponibilité est terminée (sa période est passée).
    func isPast(_ supply: VendorSupply) -> Bool { supply.availableTo < now() }

    private func apply(_ supplies: [VendorSupply]) {
        state = .from(supplies.sorted { ($0.availableFrom, $0.createdAt) < ($1.availableFrom, $1.createdAt) })
    }

    // MARK: Textes

    /// « du 3 déc. au 17 déc. »
    nonisolated static func periodText(from: Date, to: Date) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(AppLanguage.formattingLocale)
        return String(localized: "du \(from.formatted(style)) au \(to.formatted(style))")
    }
}
