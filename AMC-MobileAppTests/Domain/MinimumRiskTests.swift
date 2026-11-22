import Foundation
import Testing
@testable import AMC_MobileApp

/// RQ-050 (T-104) : mise en garde quand le minimum de lancement risque de ne pas être atteint.
struct MinimumRiskTests {
    static let day: TimeInterval = 24 * 3600
    static let deadline = Date(timeIntervalSince1970: 1_795_000_000)
    /// Commande ouverte 7 jours avant la date limite.
    static let openedAt = deadline.addingTimeInterval(-7 * day)

    static let offer = Offer(
        id: "o1", vendorId: "v1", productId: "p1", totalShares: 40, shareUnit: "10 kg",
        tiers: [PriceTier(minShares: 10, priceCents: 1_150), PriceTier(minShares: 20, priceCents: 990)],
        minimumSharesToLaunch: 10, deadline: deadline, zones: [], status: .active
    )

    static func order(committed: Int, status: GroupOrder.Status = .open) -> GroupOrder {
        GroupOrder(id: "go1", groupId: "g1", offerId: "o1", status: status, currentTierIndex: nil,
                   committedShares: committed, committedHouseholds: 0, pickupPointId: nil, pickupSlots: [])
    }

    static func assess(committed: Int, daysLeft: Double, status: GroupOrder.Status = .open,
                       openedAt: Date? = openedAt) -> MinimumRisk.Assessment {
        MinimumRisk.assess(offer: offer, order: order(committed: committed, status: status),
                           now: deadline.addingTimeInterval(-daysLeft * day), openedAt: openedAt)
    }

    // MARK: Cas limites

    @Test func minimumAlreadyReachedShowsNothing() {
        let risk = Self.assess(committed: 10, daysLeft: 1, status: .reached)
        #expect(risk.level == .none)
        #expect(risk.missingShares == 0)
        #expect(risk.message == nil)
    }

    @Test func minimumReachedEvenAfterDeadlineShowsNothing() {
        let risk = Self.assess(committed: 12, daysLeft: -1, status: .reached)
        #expect(risk.level == .none)
        #expect(risk.message == nil)
    }

    @Test func pastDeadlineBelowMinimumIsHigh() {
        let risk = Self.assess(committed: 4, daysLeft: -0.5)
        #expect(risk.level == .high)
        #expect(risk.missingShares == 6)
        #expect(risk.timeRemaining == 0)
        #expect(risk.message == "Date limite passée : il manquait 6 parts")
    }

    @Test func deadlineExactlyNowIsTreatedAsPast() {
        let risk = Self.assess(committed: 9, daysLeft: 0)
        #expect(risk.level == .high)
        #expect(risk.message == "Date limite passée : il manquait 1 part")
    }

    @Test func noSharesMidCollectionIsHigh() {
        let risk = Self.assess(committed: 0, daysLeft: 2)
        #expect(risk.level == .high)
        #expect(risk.missingShares == 10)
        #expect(risk.projectedShares == 0)
        #expect(risk.message == "Il manque 10 parts pour commander · plus que 2 jours")
    }

    @Test func noSharesRightAfterOpeningIsOnlyLow() {
        let risk = Self.assess(committed: 0, daysLeft: 6.5)
        #expect(risk.level == .low)
        #expect(risk.message == "Il manque 10 parts pour commander · plus que 6 jours")
    }

    @Test func closedOrCancelledOrdersShowNothing() {
        for status in [GroupOrder.Status.closed, .cancelled, .delivered] {
            #expect(Self.assess(committed: 2, daysLeft: 1, status: status).level == .none)
        }
    }

    // MARK: Projection

    @Test func slowPaceIsHigh() {
        // 4 parts en 5 jours, 2 jours restants : projection 4 + 0,8 × 2 = 5 < 10.
        let risk = Self.assess(committed: 4, daysLeft: 2)
        #expect(risk.level == .high)
        #expect(risk.projectedShares == 5)
        #expect(risk.message == "Il manque 6 parts pour commander · plus que 2 jours")
    }

    @Test func justEnoughPaceIsLow() {
        // 6 parts en 4 jours, 3 restants : projection 6 + 1,5 × 3 = 10 (pile le minimum, sous la marge de 20 %).
        let risk = Self.assess(committed: 6, daysLeft: 3)
        #expect(risk.level == .low)
        #expect(risk.projectedShares == 10)
        #expect(risk.message == "Il manque 4 parts pour commander · plus que 3 jours")
    }

    @Test func comfortablePaceShowsNothing() {
        // 8 parts en 4 jours, 3 restants : projection 14 ≥ 12.
        let risk = Self.assess(committed: 8, daysLeft: 3)
        #expect(risk.level == .none)
        #expect(risk.missingShares == 2)
        #expect(risk.message == nil)
    }

    @Test func unknownOpeningAssumesOneWeekOfCollection() {
        let known = Self.assess(committed: 4, daysLeft: 2)
        let unknown = Self.assess(committed: 4, daysLeft: 2, openedAt: nil)
        #expect(unknown == known)
    }

    @Test func openingAfterNowIsClampedToNow() {
        let risk = Self.assess(committed: 1, daysLeft: 2, openedAt: Self.deadline)
        #expect(risk.level == .low)
        #expect(risk.missingShares == 9)
    }

    @Test func levelsAreOrdered() {
        #expect(MinimumRisk.Level.none < .low)
        #expect(MinimumRisk.Level.low < .high)
    }

    // MARK: Message

    @Test func durationPhrases() {
        #expect(MinimumRisk.durationPhrase(2 * Self.day + 3600) == "plus que 2 jours")
        #expect(MinimumRisk.durationPhrase(Self.day) == "plus que 1 jour")
        #expect(MinimumRisk.durationPhrase(5 * 3600) == "plus que 5 heures")
        #expect(MinimumRisk.durationPhrase(3600) == "plus que 1 heure")
        #expect(MinimumRisk.durationPhrase(1_200) == "moins d'une heure")
    }

    @Test func oneMissingShareIsSingular() {
        let risk = Self.assess(committed: 9, daysLeft: 0.25)
        #expect(risk.missingShares == 1)
        #expect(risk.message?.hasPrefix("Il manque 1 part pour commander · plus que 6 heures") == true)
    }
}
