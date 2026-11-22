import Foundation
import Testing
@testable import AMC_MobileApp

/// Avis des familles sur les groupes (T-174) : dépôt fake (agrégats, éligibilité) et ViewModel.
@MainActor
struct GroupRatingsTests {
    private typealias ID = FakeData.ID
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func model(_ repositories: AppRepositories, group: String, household: String = ID.aminaHousehold) -> GroupRatingsViewModel {
        GroupRatingsViewModel(repositories: repositories, groupId: group, householdId: household, userId: ID.amina,
                              now: { [now] in now })
    }

    @Test func demoAggregatesMatchDemoRatings() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let group = try await repositories.groups.group(id: ID.saintMichel)
        let ratings = try await repositories.groups.ratings(ofGroup: ID.saintMichel)
        #expect(group.ratingCount == ratings.count)
        #expect(group.ratingSum == ratings.reduce(0) { $0 + $1.rating })
        #expect(group.ratingSummary.average == RatingRules.summary(ofRatings: ratings.map(\.rating)).average)
    }

    @Test func memberRatesThenEditsAndAggregatesFollow() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let before = try await repositories.groups.group(id: ID.saintMichel)
        let ratings = model(repositories, group: ID.saintMichel)
        await ratings.load(isMember: true)
        #expect(ratings.state.value?.eligibility == .member)
        #expect(ratings.state.value?.myRating == nil)

        let created = try await ratings.save(rating: 4, comment: "  Super groupe  ").get()
        #expect(created.ratingCount == (before.ratingCount ?? 0) + 1)
        #expect(created.ratingSum == (before.ratingSum ?? 0) + 4)
        let mine = try #require(ratings.state.value?.myRating)
        #expect(mine.comment == "Super groupe")
        #expect(mine.authorName == "Amina B.")
        #expect(ratings.state.value?.eligibility == .alreadyRated)

        let edited = try await ratings.save(rating: 2, comment: "").get()
        #expect(edited.ratingCount == created.ratingCount)
        #expect(edited.ratingSum == (created.ratingSum ?? 0) - 2)
        #expect(ratings.state.value?.myRating?.comment == nil)
        #expect(ratings.state.value?.myRating?.createdAt == mine.createdAt)
    }

    @Test func neverMemberCannotRate() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let ratings = model(repositories, group: ID.hochelaga)
        await ratings.load(isMember: false)
        #expect(ratings.state.value?.eligibility == .notEligible)
        #expect(ratings.state.value?.summary.count == 3)
        if case .failure(let error) = await ratings.save(rating: 5, comment: "") {
            #expect(error == .permissionDenied)
        } else {
            Issue.record("Un ménage jamais membre ne doit pas pouvoir noter.")
        }
    }

    @Test func formerMemberWithAShareInADeliveredOrderCanRate() async throws {
        var data = FakeData.montreal
        let order = GroupOrder(id: "order-hochelaga-passee", groupId: ID.hochelaga, offerId: ID.potatoOffer,
                               status: .delivered, currentTierIndex: nil, committedShares: 2, committedHouseholds: 1,
                               pickupPointId: nil, pickupSlots: [])
        data.groupOrders.append(order)
        data.shares[order.id] = [Share(householdId: ID.aminaHousehold, quantity: 2, finalPriceCents: 1_400, isPaid: true,
                                       suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: true)]
        let repositories = AppRepositories.fake(behavior: .instant, data: data)
        let ratings = model(repositories, group: ID.hochelaga)
        await ratings.load(isMember: false)
        #expect(ratings.state.value?.eligibility == .formerMember(groupOrderId: order.id))

        let group = try await ratings.save(rating: 5, comment: "Merci pour tout").get()
        #expect(group.ratingCount == 4)
        #expect(ratings.state.value?.myRating?.groupOrderId == order.id)
    }

    @Test func fakeRepositoryRejectsWhatTheRulesReject() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let base = GroupRating(id: ID.aminaHousehold, groupId: ID.hochelaga, householdId: ID.aminaHousehold,
                               authorName: "Amina B.", rating: 4, comment: nil, groupOrderId: nil,
                               createdAt: now, updatedAt: now)
        await #expect(throws: AppError.permissionDenied) { try await repositories.groups.saveRating(base) }
        var outOfRange = base
        outOfRange.groupId = ID.saintMichel
        outOfRange.rating = 6
        await #expect(throws: AppError.self) { try await repositories.groups.saveRating(outOfRange) }
        var unknownGroup = base
        unknownGroup.groupId = "group-inconnu"
        await #expect(throws: AppError.notFound) { try await repositories.groups.saveRating(unknownGroup) }
    }

    @Test func cachedRepositoryRefreshesTheGroupAfterARating() async throws {
        let repositories = AppRepositories.fake(behavior: .instant).cached()
        let before = try await repositories.groups.group(id: ID.saintMichel)
        let rating = GroupRating(id: ID.aminaHousehold, groupId: ID.saintMichel, householdId: ID.aminaHousehold,
                                 authorName: "Amina B.", rating: 5, comment: nil, groupOrderId: nil,
                                 createdAt: now, updatedAt: now)
        try await repositories.groups.saveRating(rating)
        let after = try await repositories.groups.group(id: ID.saintMichel)
        #expect(after.ratingCount == (before.ratingCount ?? 0) + 1)
    }
}
