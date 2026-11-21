import Foundation
import Testing
@testable import AMC_MobileApp

/// Tests de VolunteerDelivery (RQ-069, T-117).
struct VolunteerDeliveryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func order(_ status: GroupOrder.Status = .delivered) -> GroupOrder {
        var order = TierEngineTests.order(committed: 5, status: status)
        order.id = "go1"
        return order
    }

    private func share(_ household: String = "h1", pickedUp: Bool = false) -> Share {
        var share = TierEngineTests.share(household, 2)
        share.isPickedUp = pickedUp
        return share
    }

    private func window(startIn minutes: Double = 60, length: Double = 90) -> VolunteerDelivery.Window {
        let start = now.addingTimeInterval(minutes * 60)
        return .init(start: start, end: start.addingTimeInterval(length * 60))
    }

    private func input(id: String = "r1", senior: Bool = true, mobility: Bool = false,
                       share: Share? = nil, window: VolunteerDelivery.Window? = nil,
                       address: String = "4521 rue Jarry Est, app. 3") -> VolunteerDelivery.NewRequest {
        .init(id: id, groupId: "g1", order: order(), share: share ?? self.share(), householdName: "Mme Tremblay",
              householdGeohash: "f25dvgmxyz", window: window ?? self.window(), seniorMode: senior,
              reducedMobility: mobility, address: address, instructions: " sonnette 3 ", note: nil)
    }

    private func requested() throws -> VolunteerDelivery.Request {
        try VolunteerDelivery.request(input(), existing: [], now: now).request
    }

    private func claimed() throws -> VolunteerDelivery.Request {
        try VolunteerDelivery.claim(try requested(), volunteerHouseholdId: "v1", volunteerName: "Karim",
                                    volunteerGroupIds: ["g1"], all: [], now: now)
    }

    // MARK: - Éligibilité et demande

    @Test func eligibilityNeedsSeniorModeOrReducedMobility() {
        #expect(VolunteerDelivery.eligibility(seniorMode: true, reducedMobility: true) == .senior)
        #expect(VolunteerDelivery.eligibility(seniorMode: false, reducedMobility: true) == .reducedMobility)
        #expect(VolunteerDelivery.eligibility(seniorMode: false, reducedMobility: false) == nil)
        #expect(throws: AppError.self) {
            try VolunteerDelivery.request(input(senior: false), existing: [], now: now)
        }
    }

    @Test func sharedRequestNeverHoldsTheExactAddress() throws {
        let (request, address) = try VolunteerDelivery.request(input(), existing: [], now: now)
        #expect(request.geohash == "f25dvg")
        #expect(request.status == .requested)
        #expect(address.address == "4521 rue Jarry Est, app. 3")
        #expect(address.instructions == "sonnette 3")
        let encoded = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        #expect(!encoded.contains("Jarry"))
    }

    @Test func requestRejectsMissingSharePickedUpShareEmptyAddressAndDuplicates() throws {
        var noShare = input()
        noShare.share = nil
        #expect(throws: AppError.self) { try VolunteerDelivery.request(noShare, existing: [], now: now) }
        #expect(throws: AppError.self) {
            try VolunteerDelivery.request(input(share: share(pickedUp: true)), existing: [], now: now)
        }
        #expect(throws: AppError.self) { try VolunteerDelivery.request(input(address: "  "), existing: [], now: now) }
        let first = try requested()
        #expect(throws: AppError.self) { try VolunteerDelivery.request(input(id: "r2"), existing: [first], now: now) }
    }

    @Test func windowMustBeLongEnoughShortEnoughAndInTheFuture() {
        for bad in [window(length: 10), window(length: 300), window(startIn: -200), window(startIn: 15 * 24 * 60)] {
            #expect(throws: AppError.self) { try VolunteerDelivery.validatedWindow(bad, now: now) }
        }
        #expect((try? VolunteerDelivery.validatedWindow(window(), now: now)) != nil)
    }

    // MARK: - Bénévole

    @Test func claimRules() throws {
        let request = try requested()
        #expect(throws: AppError.self) {
            try VolunteerDelivery.claim(request, volunteerHouseholdId: "h1", volunteerName: "Moi",
                                        volunteerGroupIds: ["g1"], all: [], now: now)
        }
        #expect(throws: AppError.self) {
            try VolunteerDelivery.claim(request, volunteerHouseholdId: "v1", volunteerName: "Karim",
                                        volunteerGroupIds: ["autre"], all: [], now: now)
        }
        let claimed = try claimed()
        #expect(claimed.status == .claimed && claimed.volunteerHouseholdId == "v1")
        #expect(throws: AppError.self) {
            try VolunteerDelivery.claim(claimed, volunteerHouseholdId: "v2", volunteerName: "Léa",
                                        volunteerGroupIds: ["g1"], all: [], now: now)
        }
    }

    @Test func volunteerLimitAndOverlappingWindows() throws {
        var busy: [VolunteerDelivery.Request] = []
        for index in 0..<VolunteerDelivery.maxActivePerVolunteer {
            var other = try requested()
            other.id = "busy\(index)"
            other.status = .claimed
            other.volunteerHouseholdId = "v1"
            other.window = window(startIn: Double(600 + index * 300))
            busy.append(other)
        }
        #expect(!VolunteerDelivery.canTakeMore("v1", in: busy))
        #expect(throws: AppError.self) {
            try VolunteerDelivery.claim(try requested(), volunteerHouseholdId: "v1", volunteerName: "Karim",
                                        volunteerGroupIds: ["g1"], all: busy, now: now)
        }
        var overlapping = busy[0]
        overlapping.window = window(startIn: 30)
        #expect(throws: AppError.self) {
            try VolunteerDelivery.claim(try requested(), volunteerHouseholdId: "v1", volunteerName: "Karim",
                                        volunteerGroupIds: ["g1"], all: [overlapping], now: now)
        }
    }

    @Test func addressRevealedOnlyToRequesterAndClaimingVolunteer() throws {
        let (request, address) = try VolunteerDelivery.request(input(), existing: [], now: now)
        #expect(VolunteerDelivery.revealedAddress(for: request, viewerHouseholdId: "v1", addresses: [address]) == nil)
        #expect(VolunteerDelivery.revealedAddress(for: request, viewerHouseholdId: "h1", addresses: [address]) != nil)
        let claimed = try claimed()
        #expect(VolunteerDelivery.revealedAddress(for: claimed, viewerHouseholdId: "v1", addresses: [address]) != nil)
        #expect(VolunteerDelivery.revealedAddress(for: claimed, viewerHouseholdId: "v2", addresses: [address]) == nil)
        var delivered = claimed
        delivered.status = .delivered
        #expect(!VolunteerDelivery.canSeeAddress(delivered, viewerHouseholdId: "v1"))
    }

    @Test func fullFlowUsesPickupDeskAndEndsConfirmed() throws {
        let claimed = try claimed()
        #expect(VolunteerDelivery.pickupCode(for: claimed, viewerHouseholdId: "v1") != nil)
        #expect(VolunteerDelivery.pickupCode(for: claimed, viewerHouseholdId: "v2") == nil)
        #expect(throws: AppError.self) {
            try VolunteerDelivery.startRoute(claimed, by: "v1", order: order(.open), shares: [share()], now: now)
        }
        let (onTheWay, pickedShare) = try VolunteerDelivery.startRoute(
            claimed, by: "v1", order: order(), shares: [share()], now: now
        )
        #expect(onTheWay.status == .onTheWay && pickedShare.isPickedUp)
        #expect(throws: AppError.self) { try VolunteerDelivery.cancel(onTheWay, by: "h1", now: now) }
        let delivered = try VolunteerDelivery.deliver(onTheWay, by: "v1", now: now)
        let confirmed = try VolunteerDelivery.confirmReceipt(delivered, by: "h1", now: now)
        #expect(confirmed.receiptConfirmedAt == now)
        let allDone = VolunteerDelivery.steps(of: confirmed).allSatisfy { $0.isDone }
        #expect(allDone)
    }

    @Test func releaseAndCancel() throws {
        let released = try VolunteerDelivery.release(try claimed(), by: "v1")
        #expect(released.status == .requested && released.volunteerHouseholdId == nil)
        #expect(throws: AppError.self) { try VolunteerDelivery.release(try claimed(), by: "v2") }
        #expect(try VolunteerDelivery.cancel(try claimed(), by: "h1", now: now).status == .cancelled)
        #expect(throws: AppError.self) { try VolunteerDelivery.cancel(try claimed(), by: "v1", now: now) }
    }

    @Test func openRequestsExcludeOwnTakenAndExpired() throws {
        let mine = try requested()
        var other = mine
        other.id = "r2"; other.householdId = "h2"
        var expired = other
        expired.id = "r3"; expired.window = window(startIn: -300)
        let taken = try claimed()
        let open = VolunteerDelivery.openRequests(groupId: "g1", for: "h1", in: [mine, other, expired, taken], now: now)
        #expect(open.map(\.id) == ["r2"])
    }
}
