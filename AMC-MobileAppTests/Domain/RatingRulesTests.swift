import Foundation
import Testing
@testable import AMC_MobileApp

/// Notes 1 à 5 étoiles communes (T-157, T-174) et règles des avis de groupe (T-174).
struct RatingRulesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func rating(_ stars: Int, household: String = "h", comment: String? = nil, daysAgo: Double = 1,
                        groupOrderId: String? = nil) -> GroupRating {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        return GroupRating(id: household, groupId: "g", householdId: household, authorName: "A.", rating: stars,
                           comment: comment, groupOrderId: groupOrderId, createdAt: date, updatedAt: date)
    }

    @Test func summaryFromAggregatesRoundsAndRejectsNonsense() {
        #expect(RatingRules.summary(sum: 23, count: 5).average == 4.6)
        #expect(RatingRules.summary(sum: 23, count: 5).count == 5)
        #expect(RatingRules.summary(sum: 23, count: 5).hasDistribution == false)
        #expect(RatingRules.summary(sum: nil, count: nil) == .empty)
        #expect(RatingRules.summary(sum: 0, count: 0) == .empty)
        // Moyenne impossible (agrégats corrompus) : pas de note plutôt qu'une note fausse.
        #expect(RatingRules.summary(sum: 40, count: 2) == .empty)
        #expect(RatingRules.summary(sum: 1, count: 3) == .empty)
    }

    @Test func summaryOfRatingsKeepsDistribution() {
        let summary = RatingRules.summary(ofRatings: [5, 4, 4, 9, 0])
        #expect(summary.average == 4.3)
        #expect(summary.distribution == [0, 0, 0, 2, 1])
        #expect(summary.hasDistribution)
    }

    @Test func aggregateDeltaCountsANewRatingOnceAndAnEditByTheDifference() {
        let created = RatingRules.aggregateDelta(previous: nil, new: 4)
        #expect(created.sum == 4 && created.count == 1)
        let edited = RatingRules.aggregateDelta(previous: 4, new: 2)
        #expect(edited.sum == -2 && edited.count == 0)
        let same = RatingRules.aggregateDelta(previous: 3, new: 3)
        #expect(same.sum == 0 && same.count == 0)
    }

    @Test func commentIsCollapsedTrimmedAndLimited() {
        #expect(RatingRules.normalizedComment("   \n  ", maxLength: 280) == nil)
        #expect(RatingRules.normalizedComment("  Super    groupe \n\n\n\n Merci  ", maxLength: 280) == "Super groupe\nMerci")
        #expect(RatingRules.normalizedComment(String(repeating: "a", count: 400), maxLength: 280)?.count == 280)
    }

    @Test func vendorRulesStillDelegate() {
        #expect(VendorReviewRules.authorName(fromDisplayName: "Amina Benali") == "Amina B.")
        #expect(VendorReviewRules.normalizedComment("  ok  ") == "ok")
    }

    @Test func eligibilityPrefersExistingThenMembershipThenProof() {
        #expect(GroupRatingRules.eligibility(householdId: "h", isMember: true, existing: rating(4), ordersWithMyShare: []) == .alreadyRated)
        #expect(GroupRatingRules.eligibility(householdId: "h", isMember: true, existing: nil, ordersWithMyShare: ["o"]) == .member)
        #expect(GroupRatingRules.eligibility(householdId: "h", isMember: false, existing: nil, ordersWithMyShare: ["o", "p"])
                == .formerMember(groupOrderId: "o"))
        #expect(GroupRatingRules.eligibility(householdId: "h", isMember: false, existing: nil, ordersWithMyShare: []) == .notEligible)
        #expect(GroupRatingRules.eligibility(householdId: "", isMember: true, existing: nil, ordersWithMyShare: []) == .notEligible)
    }

    @Test func finishedOrdersKeepOnlyDeliveredOrClosedOrdersOfTheGroup() {
        func order(_ id: String, _ group: String, _ status: GroupOrder.Status) -> GroupOrder {
            GroupOrder(id: id, groupId: group, offerId: "x", status: status, currentTierIndex: nil, committedShares: 1,
                       committedHouseholds: 1, pickupPointId: nil, pickupSlots: [])
        }
        let orders = [order("a", "g", .delivered), order("b", "g", .open), order("c", "g", .closed),
                      order("d", "autre", .delivered), order("e", "g", .cancelled)]
        #expect(GroupRatingRules.finishedOrders(orders, ofGroup: "g").map(\.id) == ["a", "c"])
    }

    @Test func makeRatingValidatesAndKeepsCreationAndProofOnEdit() throws {
        #expect(throws: AppError.self) {
            try GroupRatingRules.makeRating(groupId: "g", householdId: "h", authorName: "A.", rating: 0, comment: "",
                                            eligibility: .member, existing: nil, now: now)
        }
        #expect(throws: AppError.permissionDenied) {
            try GroupRatingRules.makeRating(groupId: "g", householdId: "h", authorName: "A.", rating: 4, comment: "",
                                            eligibility: .notEligible, existing: nil, now: now)
        }
        let former = try GroupRatingRules.makeRating(groupId: "g", householdId: "h", authorName: "A.", rating: 4,
                                                     comment: "  Bien  ", eligibility: .formerMember(groupOrderId: "o"),
                                                     existing: nil, now: now)
        #expect(former.id == "h")
        #expect(former.groupOrderId == "o")
        #expect(former.comment == "Bien")
        #expect(former.createdAt == now)

        let existing = rating(5, daysAgo: 10, groupOrderId: "o")
        let later = now.addingTimeInterval(60)
        let edited = try GroupRatingRules.makeRating(groupId: "g", householdId: "h", authorName: "A.", rating: 3,
                                                     comment: "", eligibility: .alreadyRated, existing: existing, now: later)
        #expect(edited.createdAt == existing.createdAt)
        #expect(edited.updatedAt == later)
        #expect(edited.groupOrderId == "o")
        #expect(edited.comment == nil)
    }

    @Test func validateRejectsForeignIdsAndLongComments() throws {
        try GroupRatingRules.validate(rating(4))
        var wrongId = rating(4)
        wrongId.id = "autre"
        #expect(throws: AppError.permissionDenied) { try GroupRatingRules.validate(wrongId) }
        #expect(throws: AppError.permissionDenied) {
            try GroupRatingRules.validate(rating(4, comment: String(repeating: "x", count: 281)))
        }
    }

    @Test func recentShowsCommentedRatingsFirstThenNewest() {
        let ratings = [rating(5, household: "a", daysAgo: 1), rating(4, household: "b", comment: "Top", daysAgo: 5),
                       rating(3, household: "c", comment: "Bien", daysAgo: 2), rating(2, household: "d", daysAgo: 0)]
        #expect(GroupRatingRules.recent(ratings, limit: 3).map(\.householdId) == ["c", "b", "d"])
    }

    @Test func applyingMovesAggregatesByTheExactDifference() {
        var group = FakeData.montreal.groups[0]
        group.ratingSum = nil
        group.ratingCount = nil
        let first = GroupRatingRules.applying(rating(4), replacing: nil, to: group)
        #expect(first.ratingSum == 4)
        #expect(first.ratingCount == 1)
        let edited = GroupRatingRules.applying(rating(2), replacing: rating(4), to: first)
        #expect(edited.ratingSum == 2)
        #expect(edited.ratingCount == 1)
        #expect(edited.ratingSummary.average == 2)
    }
}
