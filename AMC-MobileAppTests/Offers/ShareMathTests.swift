import Foundation
import Testing
@testable import AMC_MobileApp

struct ShareMathTests {
    let tier = PriceTier(minShares: 11, priceCents: 260)

    private func offer(totalShares: Int = 200, unit: String = "kg") -> Offer {
        Offer(id: "o", vendorId: "v", productId: "p", totalShares: totalShares, shareUnit: unit,
              tiers: [PriceTier(minShares: 1, priceCents: 320), tier], minimumSharesToLaunch: 10,
              deadline: .now, zones: [], status: .active)
    }

    @Test func totalIsSharesTimesCurrentTierPrice() {
        #expect(ShareMath.total(shares: 10, tier: tier) == 2_600)
        #expect(ShareMath.total(shares: 0, tier: tier) == 0)
        #expect(ShareMath.total(shares: -3, tier: tier) == 0)
    }

    @Test func savingsVersusGrocery() {
        // Maquette F3 : 10 kg à 2,60 $ au lieu de 4,10 $ → 15 $ économisés.
        #expect(ShareMath.savings(shares: 10, tier: tier, referencePriceCents: 410) == 1_500)
        #expect(ShareMath.savings(shares: 10, tier: tier, referencePriceCents: 200) == 0)
    }

    @Test func quoteBundlesEverything() {
        let quote = ShareMath.quote(shares: 20, tier: tier, referencePriceCents: 410)
        #expect(quote == ShareMath.Quote(shares: 20, totalCents: 5_200, groceryCents: 8_200, savingsCents: 3_000))
    }

    @Test func boundsAndClamp() {
        #expect(ShareMath.bounds(for: offer()) == 1...200)
        #expect(ShareMath.bounds(for: offer(), minimum: 5, maximum: 40) == 5...40)
        #expect(ShareMath.bounds(for: offer(totalShares: 30), maximum: 99) == 1...30)
        #expect(ShareMath.bounds(for: offer(totalShares: 0)) == 1...1)
        #expect(ShareMath.clamp(0, to: 1...40) == 1)
        #expect(ShareMath.clamp(55, to: 1...40) == 40)
        #expect(ShareMath.clamp(12, to: 1...40) == 12)
    }

    @Test func defaultSteps() {
        #expect(ShareMath.defaultSteps(for: "kg", in: 1...200) == [5, 10, 20])
        #expect(ShareMath.defaultSteps(for: "kg", in: 1...12) == [5, 10])
        #expect(ShareMath.defaultSteps(for: "sac de 10 kg", in: 1...30) == [1, 2, 3])
        #expect(ShareMath.defaultSteps(for: "douzaine", in: 1...2) == [1, 2])
        #expect(ShareMath.defaultSteps(for: "kg", in: 1...3) == [1])
    }

    @Test func unitWeight() {
        #expect(ShareMath.unitWeightKg("kg") == 1)
        #expect(ShareMath.unitWeightKg("10 kg") == 10)
        #expect(ShareMath.unitWeightKg("sac de 10 kg") == 10)
        #expect(ShareMath.unitWeightKg("caisse de 2,5 kg") == 2.5)
        #expect(ShareMath.unitWeightKg("douzaine") == nil)
    }

    @Test func quantityLabels() {
        #expect(ShareMath.quantityLabel(shares: 10, unit: "kg") == "10 kg")
        #expect(ShareMath.quantityLabel(shares: 2, unit: "sac de 10 kg") == "20 kg")
        #expect(ShareMath.quantityLabel(shares: 3, unit: "caisse de 2,5 kg") == "7,5 kg")
        #expect(ShareMath.quantityLabel(shares: 1, unit: "douzaine") == "1 douzaine")
        #expect(ShareMath.quantityLabel(shares: 3, unit: "douzaine") == "3 douzaines")
        #expect(ShareMath.pluralized("caisse de pommes") == "caisses de pommes")
        #expect(ShareMath.pluralized("lots") == "lots")
    }
}
