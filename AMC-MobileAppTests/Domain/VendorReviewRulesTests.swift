import Foundation
import Testing
@testable import AMC_MobileApp

/// Avis producteurs (T-157) : moyenne, éligibilité, confiance, validation.
struct VendorReviewRulesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func review(_ rating: Int, household: String = "h", daysAgo: Double = 1) -> VendorReview {
        let date = now.addingTimeInterval(-daysAgo * day)
        return VendorReview(id: "v_\(household)", vendorId: "v", householdId: household, authorName: "A.", rating: rating,
                            comment: nil, groupOrderId: "o", createdAt: date, updatedAt: date)
    }

    private func sale(_ id: String, vendor: String = "v", daysAgo: Double, households: Int = 10,
                      buyers: Set<String> = []) -> VendorSale {
        VendorSale(id: id, vendorId: vendor, offerId: "offer-\(id)", productName: id, shareLabel: "sac", shares: 20,
                   households: households, date: now.addingTimeInterval(-daysAgo * day), buyerHouseholdIds: buyers)
    }

    @Test func emptySummaryHasNoAverage() {
        let summary = VendorReviewRules.summary(of: [])
        #expect(summary.average == nil)
        #expect(summary.count == 0)
        #expect(summary.share(of: 5) == 0)
    }

    @Test func averageIsRoundedToOneDecimalAndIgnoresInvalidRatings() {
        let summary = VendorReviewRules.summary(of: [review(5), review(4), review(4), review(0), review(9)])
        #expect(summary.count == 3)
        #expect(summary.average == 4.3)
        #expect(summary.distribution == [0, 0, 0, 2, 1])
        #expect(summary.share(of: 4) == 2.0 / 3.0)
    }

    @Test func recentReviewsAreNewestFirstAndLimited() {
        let reviews = (1...8).map { review(3, household: "h\($0)", daysAgo: Double($0)) }
        let recent = VendorReviewRules.recent(reviews, limit: 3)
        #expect(recent.map(\.householdId) == ["h1", "h2", "h3"])
    }

    @Test func onlyABuyerOfThisVendorIsEligible() {
        let sales = [
            sale("old", daysAgo: 30, buyers: ["amina"]),
            sale("new", daysAgo: 3, buyers: ["amina", "karim"]),
            sale("other", vendor: "w", daysAgo: 1, buyers: ["zoe"]),
        ]
        #expect(VendorReviewRules.eligibleSale(for: "amina", vendorId: "v", in: sales)?.id == "new")
        #expect(VendorReviewRules.eligibleSale(for: "zoe", vendorId: "v", in: sales) == nil)
        #expect(VendorReviewRules.eligibleSale(for: "", vendorId: "v", in: sales) == nil)
        #expect(VendorReviewRules.eligibleSale(for: "amina", vendorId: "v", in: []) == nil)
    }

    @Test func trustCountsLotsFamiliesAndSeniority() {
        let sales = [sale("a", daysAgo: 40, households: 12), sale("b", daysAgo: 5, households: 8)]
        let trust = VendorReviewRules.trust(sales: sales, memberSince: nil)
        #expect(trust.deliveredLots == 2)
        #expect(trust.familiesServed == 20)
        #expect(trust.lastSale?.id == "b")
        #expect(trust.since == sales[0].date)

        let since = now.addingTimeInterval(-400 * day)
        #expect(VendorReviewRules.trust(sales: sales, memberSince: since).since == since)
        #expect(VendorReviewRules.trust(sales: [], memberSince: nil).lastSale == nil)
    }

    @Test func makeReviewValidatesAndKeepsCreationDate() throws {
        #expect(throws: AppError.self) {
            try VendorReviewRules.makeReview(vendorId: "v", householdId: "h", authorName: "A.", rating: 6, comment: "",
                                             groupOrderId: "o", existing: nil, now: now)
        }
        let first = try VendorReviewRules.makeReview(vendorId: "v", householdId: "h", authorName: "A.", rating: 5,
                                                     comment: "   ", groupOrderId: "o", existing: nil, now: now)
        #expect(first.id == "v_h")
        #expect(first.comment == nil)
        let later = now.addingTimeInterval(day)
        let edited = try VendorReviewRules.makeReview(vendorId: "v", householdId: "h", authorName: "A.", rating: 3,
                                                      comment: String(repeating: "x", count: 900), groupOrderId: "autre",
                                                      existing: first, now: later)
        #expect(edited.createdAt == now)
        #expect(edited.updatedAt == later)
        #expect(edited.groupOrderId == "o")
        #expect(edited.comment?.count == VendorReview.maxCommentLength)
    }

    @Test func authorNameKeepsFirstNameAndInitial() {
        #expect(VendorReviewRules.authorName(fromDisplayName: "Amina Benali") == "Amina B.")
        #expect(VendorReviewRules.authorName(fromDisplayName: "Jean-Pierre de la Fontaine") == "Jean-Pierre F.")
        #expect(VendorReviewRules.authorName(fromDisplayName: "Zoé") == "Zoé")
        #expect(VendorReviewRules.authorName(fromDisplayName: "  ") == "Une famille")
    }

    @Test func seniorityReadsNaturally() {
        #expect(Seniority.value(since: nil, now: now) == "Nouveau")
        #expect(Seniority.value(since: now.addingTimeInterval(-3 * day), now: now) == "3 jours")
        #expect(Seniority.value(since: now.addingTimeInterval(-800 * day), now: now) == "2 ans")
    }

    @Test func fakeRepositoryRefusesNonBuyersAndForgedIds() async throws {
        let repository = FakeVendorReviewRepository(sales: [sale("o", daysAgo: 2, buyers: ["h"])])
        var mine = review(5)
        mine.groupOrderId = "o"
        #expect(try await repository.saveReview(mine) == mine)
        var stranger = review(5, household: "x")
        stranger.groupOrderId = "o"
        await #expect(throws: AppError.permissionDenied) { try await repository.saveReview(stranger) }
        var forged = mine
        forged.id = "v_autre"
        await #expect(throws: AppError.permissionDenied) { try await repository.saveReview(forged) }
        var outOfRange = mine
        outOfRange.rating = 0
        await #expect(throws: AppError.self) { try await repository.saveReview(outOfRange) }
    }
}
