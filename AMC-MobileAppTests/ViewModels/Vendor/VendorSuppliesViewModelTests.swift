import Foundation
import Testing
@testable import AMC_MobileApp

/// S-08 « Mes disponibilités » (T-109) et lot créé depuis une disponibilité.
@MainActor
struct VendorSuppliesViewModelTests {
    private static let vendor = FakeData.ID.fermeRive
    private static let day: TimeInterval = 86_400

    private static func supply(_ category: Product.Category, from days: Double, id: String,
                               vendor: String = vendor) -> VendorSupply {
        let start = Date.now.addingTimeInterval(days * day)
        return VendorSupply(id: id, vendorId: vendor, category: category, quantity: 200, unit: .kilogram,
                            availableFrom: start, availableTo: start.addingTimeInterval(10 * day), servedZones: ["f25d"])
    }

    private static func repositories(_ supplies: [VendorSupply]) -> AppRepositories {
        var repos = AppRepositories.fake(behavior: .instant)
        repos.supplies = FakeVendorSupplyRepository(behavior: .instant, supplies: supplies)
        return repos
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Condition jamais remplie")
    }

    @Test func loadListsMySuppliesByStartDate() async throws {
        let repos = Self.repositories([
            Self.supply(.grains, from: 5, id: "s2"),
            Self.supply(.produce, from: 1, id: "s1"),
            Self.supply(.eggs, from: 2, id: "autre", vendor: "vendor-autre"),
        ])
        let model = VendorSuppliesViewModel(repositories: repos, vendorId: Self.vendor)
        await model.load()
        #expect(model.state.value?.map(\.id) == ["s1", "s2"])
    }

    @Test func noSupplyIsEmptyAndANewDraftUsesTheVendorZones() async throws {
        let repos = Self.repositories([])
        let model = VendorSuppliesViewModel(repositories: repos, vendorId: Self.vendor)
        await model.load()
        #expect(model.state == .empty)
        let zones = try await repos.vendors.vendor(id: Self.vendor).servedZones
        #expect(model.newDraft().servedZones == zones)
    }

    @Test func addEditAndRemoveASupply() async throws {
        let model = VendorSuppliesViewModel(repositories: Self.repositories([]), vendorId: Self.vendor)
        await model.load()

        var draft = model.newDraft()
        draft.category = .grains
        draft.quantity = 500
        draft.servedZones = ["f25d"]
        #expect(await model.save(draft))
        let added = try #require(model.state.value?.first)
        #expect(added.category == .grains && added.quantity == 500 && added.vendorId == Self.vendor)

        var edit = VendorSuppliesViewModel.Draft(added)
        edit.quantity = 250
        #expect(await model.save(edit))
        #expect(model.state.value?.first?.quantity == 250)
        #expect(model.state.value?.count == 1)

        await model.remove(try #require(model.state.value?.first))
        #expect(model.state == .empty)
        #expect(model.actionError == nil)
    }

    @Test func supplyWithoutZoneIsRefused() async throws {
        let model = VendorSuppliesViewModel(repositories: Self.repositories([]), vendorId: Self.vendor)
        await model.load()
        var draft = model.newDraft()
        draft.servedZones = []
        #expect(await model.save(draft) == false)
        #expect(model.actionError != nil)
    }

    @Test func aSupplyAddedElsewhereAppearsLive() async throws {
        let repos = Self.repositories([Self.supply(.produce, from: 1, id: "s1")])
        let model = VendorSuppliesViewModel(repositories: repos, vendorId: Self.vendor)
        await model.load()
        let observation = Task { await model.observe() }
        defer { observation.cancel() }
        try await waitUntil { model.isLive }
        for _ in 0..<20 { await Task.yield() }

        try await repos.supplies.addSupply(Self.supply(.grains, from: 3, id: ""))
        try await waitUntil { model.state.value?.count == 2 }
    }

    @Test func pastSupplyIsFlagged() async {
        let model = VendorSuppliesViewModel(repositories: Self.repositories([]), vendorId: Self.vendor)
        #expect(model.isPast(Self.supply(.produce, from: -20, id: "vieux")))
        #expect(!model.isPast(Self.supply(.produce, from: 1, id: "neuf")))
    }

    // MARK: Lot depuis une disponibilité

    @Test func tierEditorIsPrefilledFromASupply() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let products = try await repos.vendors.products(ofVendor: Self.vendor)
        let target = try #require(products.last)
        var supply = Self.supply(target.category, from: 1, id: "s1")
        supply.servedZones = ["f25d", "f25e"]

        let editor = TierEditorViewModel(repositories: repos, vendorId: Self.vendor)
        editor.prefill(from: supply)
        await editor.load()

        #expect(editor.zones == ["f25d", "f25e"])
        #expect(editor.selectedProduct?.category == target.category)
        #expect(editor.deadline <= supply.availableTo)
        #expect(editor.deadline >= Date.now.addingTimeInterval(Self.day - 60))
    }
}
