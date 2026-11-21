import Foundation
import Testing
@testable import AMC_MobileApp

struct OrderActivityPresentationTests {
    typealias State = GrenierOrderAttributes.ContentState

    /// Aujourd'hui à 17 h, dans le calendrier courant (celui qu'utilise GrenierFormat.hour).
    let fivePM = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now)!

    func presentation(_ stage: GrenierOrderAttributes.Stage) -> OrderActivityPresentation {
        OrderActivityPresentation(.demo, .demo(stage, pickupTime: fivePM))
    }

    func open(families: Int, next: Int?, price: Int) -> OrderActivityPresentation {
        OrderActivityPresentation(.demo, State(stage: .ouverte, committedFamilies: families, nextThreshold: next,
                                               currentPriceCents: price, pickupTime: fivePM))
    }

    @Test func titleJoinsProductAndGroup() {
        #expect(presentation(.ouverte).title == "Riz basmati · Parc-Ex Ouest")
        #expect(presentation(.palierFranchi).subtitle == "Parc-Ex Ouest · Palier débloqué")
    }

    @Test func openStageNudgesWithMissingFamiliesAndDiscount() {
        let p = presentation(.ouverte)
        #expect(p.familiesMissing == 1)
        #expect(p.nextTier?.priceCents == 210)
        #expect(p.nextDiscountPercent == 19)
        #expect(p.headline == "Encore 1 famille pour −19 %")
    }

    @Test func pluralFamilies() {
        let p = open(families: 24, next: 26, price: 260)
        #expect(p.familiesMissing == 2)
        #expect(p.headline == "Encore 2 familles pour −19 %")
        #expect(OrderActivityPresentation.families(1) == "1 famille")
        #expect(OrderActivityPresentation.families(3) == "3 familles")
    }

    @Test func firstTierNudgeTargetsSecondTier() {
        let p = open(families: 4, next: 11, price: 320)
        #expect(p.familiesMissing == 7)
        #expect(p.nextTier?.minFamilies == 11)
        #expect(p.nextDiscountPercent == 19) // 3,20 → 2,60 $
        #expect(p.currentTierIndex == 0)
    }

    @Test func lastTierReachedHasNoNextThreshold() {
        let p = open(families: 30, next: nil, price: 210)
        #expect(p.familiesMissing == 0)
        #expect(p.nextTier == nil)
        #expect(p.nextDiscountPercent == nil)
        #expect(p.headline == "Meilleur prix atteint pour Parc-Ex Ouest")
    }

    @Test func tierUnlockedShowsNewAndPreviousPrice() {
        let p = presentation(.palierFranchi)
        #expect(p.state.currentPriceCents == 210)
        #expect(p.previousPriceCents == 260)
        #expect(p.priceText.contains("2,10"))
        #expect(p.headline.hasPrefix("Palier débloqué : 2,10"))
        #expect(p.headline.hasSuffix("/kg pour tout le groupe"))
        #expect(p.detail == "Tu es la 26e famille · ta part 10 kg")
        #expect(p.alert?.title == "Palier débloqué !")
    }

    @Test func onTheWayAnnouncesTimeAndAddress() {
        let p = presentation(.enRoute)
        #expect(p.pickupTimeText == "17 h")
        #expect(p.headline == "Ta commande arrive à 17 h au 7420 rue Ogilvy")
        #expect(p.detail == "Ferme Lafleur → Chez Fatima")
        #expect(p.compactTrailingText == "17 h")
        #expect(!p.showsPrice)
        #expect(p.previousPriceCents == nil)
    }

    @Test func arrivedShowsOrderCode() {
        let p = presentation(.arrivee)
        #expect(p.detail == "Montre le code GRN-4821 à Fatima")
        #expect(p.alert?.body == "Montre le code GRN-4821 à Fatima.")
        #expect(p.segmentFills == [1, 1, 0])
        #expect(p.highlightedSegment == 1)
    }

    @Test func pickedUpIsQuiet() {
        let p = presentation(.recuperee)
        #expect(p.alert == nil)
        #expect(p.segmentFills == [1, 1, 1])
    }

    @Test func tierBarFillsAndLabels() {
        let p = presentation(.ouverte) // 25 familles
        #expect(p.segmentFills == [1, 1, 0])
        #expect(p.highlightedSegment == 1)
        #expect(p.segmentLabels.count == 3)
        #expect(p.segmentLabels[0].hasPrefix("1–10 · 3,20"))
        #expect(p.segmentLabels[1].hasPrefix("11–25 · 2,60"))
        #expect(p.segmentLabels[2].hasPrefix("26+ · 2,10"))

        let partial = open(families: 24, next: 26, price: 260)
        #expect(partial.segmentFills[1] == 14.0 / 15.0)

        let full = presentation(.palierFranchi)
        #expect(full.segmentFills == [1, 1, 1])
        #expect(full.highlightedSegment == 2)
    }

    @Test func hourFormatting() {
        let halfPast = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: .now)!
        #expect(GrenierFormat.hour(fivePM) == "17 h")
        #expect(GrenierFormat.hour(halfPast) == "18 h 30")
    }

    @MainActor @Test func priceFormattingMatchesMoney() {
        #expect(GrenierFormat.price(260) == Money.format(260))
        #expect(GrenierFormat.price(210).contains("2,10"))
    }

    @Test func demoSequenceAndPickupTime() {
        #expect(State.demoSequence == [.ouverte, .palierFranchi, .enRoute, .arrivee])
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let pickup = GrenierOrderAttributes.demoPickupTime(now: morning)
        #expect(Calendar.current.component(.hour, from: pickup) == 17)
        #expect(Calendar.current.isDate(pickup, inSameDayAs: morning))
        let lateEvening = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: .now)!
        #expect(GrenierOrderAttributes.demoPickupTime(now: lateEvening) > lateEvening)
    }

    @Test func contentStateRoundTripsThroughCodable() throws {
        let state = State.demo(.enRoute, pickupTime: fivePM)
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(State.self, from: data) == state)
        let attributes = try JSONDecoder().decode(GrenierOrderAttributes.self, from: JSONEncoder().encode(GrenierOrderAttributes.demo))
        #expect(attributes == .demo)
    }
}
