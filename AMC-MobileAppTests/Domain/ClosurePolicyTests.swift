import Foundation
import Testing
@testable import AMC_MobileApp

/// RQ-053 : tests de ClosurePolicy (clôture automatique et bouton « Fermer »).
struct ClosurePolicyTests {
    static let offer = TierEngineTests.offer
    static let deadline = TierEngineTests.deadline
    static let before = deadline.addingTimeInterval(-60)
    static let after = deadline.addingTimeInterval(60)

    static func order(committed: Int = 0, status: GroupOrder.Status = .open) -> GroupOrder {
        TierEngineTests.order(committed: committed, status: status)
    }

    static func user(household: String? = "h1", vendor: String? = nil) -> AppUser {
        AppUser(id: "u1", displayName: "Camille", photoURL: nil, language: .french, roles: [.family],
                neighborhood: "Rosemont", dietaryPreferences: [], seniorMode: false,
                householdId: household, vendorId: vendor)
    }

    static func member(_ household: String = "h1", role: GroupMember.Role) -> GroupMember {
        GroupMember(householdId: household, role: role, joinedAt: deadline)
    }

    // MARK: (a) clôture automatique

    @Test func automaticClosureIsNotDueBeforeTheDeadline() {
        #expect(!ClosurePolicy.shouldAttemptAutomaticClosure(order: Self.order(committed: 12), offer: Self.offer, now: Self.before))
        #expect(ClosurePolicy.automaticClosure(order: Self.order(committed: 12), offer: Self.offer, now: Self.before) == .notDue)
    }

    @Test func automaticClosureConfirmsAtTheReachedTier() {
        let result = ClosurePolicy.automaticClosure(order: Self.order(committed: 22, status: .reached), offer: Self.offer, now: Self.after)
        guard case .closed(let order, let outcome) = result else {
            Issue.record("Attendu .closed, obtenu \(result)")
            return
        }
        #expect(order.status == .closed)
        #expect(order.currentTierIndex == 1)
        #expect(outcome == .confirmed(tierIndex: 1, unitPriceCents: 990))
    }

    @Test func automaticClosureCancelsUnderTheMinimum() {
        let result = ClosurePolicy.automaticClosure(order: Self.order(committed: 4), offer: Self.offer, now: Self.deadline)
        guard case .closed(let order, let outcome) = result else {
            Issue.record("Attendu .closed, obtenu \(result)")
            return
        }
        #expect(order.status == .cancelled)
        #expect(outcome == .cancelled)
    }

    @Test(arguments: [GroupOrder.Status.closed, .cancelled, .delivered])
    func automaticClosureIsIdempotent(status: GroupOrder.Status) {
        let closed = Self.order(committed: 22, status: status)
        #expect(!ClosurePolicy.shouldAttemptAutomaticClosure(order: closed, offer: Self.offer, now: Self.after))
        #expect(ClosurePolicy.automaticClosure(order: closed, offer: Self.offer, now: Self.after) == .alreadyClosed(closed))
    }

    @Test func secondDeviceSeesTheOrderAlreadyClosed() {
        guard case .closed(let order, _) = ClosurePolicy.automaticClosure(
            order: Self.order(committed: 12, status: .reached), offer: Self.offer, now: Self.after
        ) else {
            Issue.record("La première clôture aurait dû fermer la commande")
            return
        }
        #expect(ClosurePolicy.automaticClosure(order: order, offer: Self.offer, now: Self.after) == .alreadyClosed(order))
    }

    // MARK: (b) bouton « Fermer »

    /// Mêmes règles que `firestore.rules` (`isGroupCoordinator` : l'uid est dans `coordinatorIds` du groupe).
    @Test func coordinatorListedInCoordinatorIdsCanCloseEarly() throws {
        let user = Self.user()
        let order = Self.order(committed: 31, status: .reached)
        #expect(ClosurePolicy.canClose(user: user, groupCoordinatorIds: ["u0", user.id], offer: Self.offer, order: order))
        let (closed, outcome) = try ClosurePolicy.close(
            user: user, groupCoordinatorIds: ["u0", user.id], offer: Self.offer, order: order
        )
        #expect(closed.status == .closed)
        #expect(outcome == .confirmed(tierIndex: 2, unitPriceCents: 850))
    }

    /// Seul l'uid compte, comme dans les règles : pas besoin d'un ménage.
    @Test func coordinatorWithoutHouseholdCanClose() {
        let user = Self.user(household: nil)
        #expect(ClosurePolicy.canClose(user: user, groupCoordinatorIds: [user.id], offer: Self.offer, order: Self.order()))
    }

    @Test func vendorCanCloseEarlyWithoutBeingAMember() throws {
        let vendor = Self.user(household: nil, vendor: "v1")
        #expect(ClosurePolicy.canClose(user: vendor, groupCoordinatorIds: [], offer: Self.offer, order: Self.order(committed: 5)))
        let (closed, outcome) = try ClosurePolicy.close(
            user: vendor, groupCoordinatorIds: [], offer: Self.offer, order: Self.order(committed: 5)
        )
        #expect(closed.status == .cancelled)
        #expect(outcome == .cancelled)
    }

    @Test func plainMemberCannotClose() {
        let user = Self.user()
        let others = ["u0", "u9"]
        #expect(!ClosurePolicy.canClose(user: user, groupCoordinatorIds: others, offer: Self.offer, order: Self.order(committed: 12)))
        #expect(throws: AppError.invalidInput(ClosurePolicy.notAllowedMessage)) {
            try ClosurePolicy.close(user: user, groupCoordinatorIds: others, offer: Self.offer, order: Self.order(committed: 12))
        }
    }

    @Test func groupWithoutCoordinatorsRefusesEveryoneButTheVendor() {
        #expect(!ClosurePolicy.canClose(user: Self.user(), groupCoordinatorIds: [], offer: Self.offer, order: Self.order()))
    }

    @Test func otherVendorCannotClose() {
        let other = Self.user(household: nil, vendor: "v2")
        #expect(!ClosurePolicy.canClose(user: other, groupCoordinatorIds: [], offer: Self.offer, order: Self.order()))
        #expect(throws: AppError.invalidInput(ClosurePolicy.notAllowedMessage)) {
            try ClosurePolicy.close(user: other, groupCoordinatorIds: [], offer: Self.offer, order: Self.order())
        }
    }

    @Test func closedOrderCannotBeClosedAgain() {
        let closed = Self.order(committed: 12, status: .closed)
        let user = Self.user()
        #expect(!ClosurePolicy.canClose(user: user, groupCoordinatorIds: [user.id], offer: Self.offer, order: closed))
        #expect(throws: AppError.orderClosed) {
            try ClosurePolicy.close(user: user, groupCoordinatorIds: [user.id], offer: Self.offer, order: closed)
        }
    }

    @Test func mismatchedOfferIsRefused() {
        var otherOffer = Self.offer
        otherOffer.id = "o2"
        let vendor = Self.user(household: nil, vendor: "v1")
        #expect(!ClosurePolicy.canClose(user: vendor, groupCoordinatorIds: [], offer: otherOffer, order: Self.order()))
        #expect(throws: AppError.invalidInput("Ce lot ne correspond pas à cette commande.")) {
            try ClosurePolicy.close(user: vendor, groupCoordinatorIds: [], offer: otherOffer, order: Self.order())
        }
    }

    @Test func notAllowedMessageIsFrench() {
        #expect(AppError.invalidInput(ClosurePolicy.notAllowedMessage).message.hasPrefix("Seuls la coordination"))
    }
}
