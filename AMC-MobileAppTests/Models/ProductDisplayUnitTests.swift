// ProductDisplayUnitTests.swift
// Unité d'un produit affichée dans la langue de l'app (« sac de 5 kg » / "bag of 5 kg") sans toucher à la valeur stockée.

import Foundation
import Testing
@testable import AMC_MobileApp

struct ProductDisplayUnitTests {
    private func product(unit: String) -> Product {
        Product(id: "p", vendorId: "v", name: "Riz", category: .grains, unit: unit, origin: "Québec", tags: [],
                photoURL: nil, referenceGroceryPriceCents: 1_999)
    }

    /// Les tests tournent en français : l'affichage est la valeur stockée.
    @Test func sameInFrench() {
        #expect(product(unit: "sac de 5 kg").displayUnit == "sac de 5 kg")
        #expect(product(unit: "kg").displayUnit == "kg")
    }

    /// Une unité libre que `ShareSpec` ne relit pas fidèlement reste telle quelle.
    @Test func freeFormUnitIsKept() {
        #expect(product(unit: "douzaine").displayUnit == "douzaine")
    }

    @Test func decimalSeparatorFollowsLanguage() {
        #expect(AppLanguage.decimalSeparator == ",")
        #expect(ProductEditorViewModel.priceText(349) == "3,49")
    }
}
