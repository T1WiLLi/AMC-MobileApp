import Foundation
import Testing
@testable import AMC_MobileApp

/// Tests de PickupDesk (RQ-066, RQ-067).
struct PickupDeskTests {
    private func order(_ status: GroupOrder.Status = .delivered, id: String = "go1") -> GroupOrder {
        var order = TierEngineTests.order(committed: 5, status: status)
        order.id = id
        return order
    }

    private func share(_ household: String, _ quantity: Int, pickedUp: Bool = false) -> Share {
        var share = TierEngineTests.share(household, quantity)
        share.qrCode = ShareAllocator.qrCode(orderId: "go1", householdId: household)
        share.isPickedUp = pickedUp
        return share
    }

    private var shares: [Share] { [share("h1", 2), share("h2", 3, pickedUp: true), share("h3", 0)] }

    // MARK: - RQ-066

    @Test func validCodeMarksTheSharePickedUp() {
        let code = ShareAllocator.qrCode(orderId: "go1", householdId: "h1")
        let result = PickupDesk.scan(code, order: order(), shares: shares)
        #expect(result.isSuccess)
        #expect(result.share?.householdId == "h1")
        #expect(result.share?.isPickedUp == true)
        #expect(result.message.contains("2 parts"))
    }

    @Test func surroundingWhitespaceIsIgnored() {
        let code = " \(ShareAllocator.qrCode(orderId: "go1", householdId: "h1"))\n"
        #expect(PickupDesk.scan(code, order: order(), shares: shares).isSuccess)
    }

    /// Fermée = en route : la part ne se remet qu'une fois la livraison marquée comme arrivée.
    @Test func closedOrderIsNotPickableUntilArrived() {
        let code = ShareAllocator.qrCode(orderId: "go1", householdId: "h1")
        #expect(PickupDesk.scan(code, order: order(.closed), shares: shares) == .orderNotReady(.closed))
    }

    @Test func alreadyPickedUpShareIsNotGivenTwice() {
        let code = ShareAllocator.qrCode(orderId: "go1", householdId: "h2")
        let result = PickupDesk.scan(code, order: order(), shares: shares)
        #expect(result == .alreadyPickedUp(shares[1]))
        #expect(!result.isSuccess)
    }

    @Test func tamperedOrGarbageCodesAreUnknown() {
        let valid = ShareAllocator.qrCode(orderId: "go1", householdId: "h1")
        let tampered = valid.replacingOccurrences(of: ":h1:", with: ":h9:")
        for code in ["", "hello", tampered, "GRENIER:go1:h1:00000000"] {
            #expect(PickupDesk.scan(code, order: order(), shares: shares) == .unknownCode)
        }
    }

    @Test func householdWithoutShareIsUnknown() {
        let noShare = ShareAllocator.qrCode(orderId: "go1", householdId: "h4")
        let zeroShare = ShareAllocator.qrCode(orderId: "go1", householdId: "h3")
        #expect(PickupDesk.scan(noShare, order: order(), shares: shares) == .unknownCode)
        #expect(PickupDesk.scan(zeroShare, order: order(), shares: shares) == .unknownCode)
    }

    @Test func codeOfAnotherOrderIsWrongOrder() {
        let code = ShareAllocator.qrCode(orderId: "go2", householdId: "h1")
        let result = PickupDesk.scan(code, order: order(), shares: shares)
        #expect(result == .wrongOrder)
        #expect(result.message.contains("autre commande"))
    }

    @Test func onlyDeliveredOrdersCanBePickedUp() {
        let code = ShareAllocator.qrCode(orderId: "go1", householdId: "h1")
        for status in [GroupOrder.Status.open, .reached, .closed, .cancelled] {
            let result = PickupDesk.scan(code, order: order(status), shares: shares)
            #expect(result == .orderNotReady(status))
            #expect(!result.message.isEmpty)
        }
        #expect(GroupOrder.Status.allCases.filter(PickupDesk.canPickUp) == [.delivered])
    }

    // MARK: - RQ-067

    @Test func checklistPutsMissingHouseholdsFirstSortedByName() {
        let checklist = PickupDesk.checklist(
            shares: [share("h1", 2, pickedUp: true), share("h2", 1), share("h3", 4), share("h4", 0), share("h5", 1, pickedUp: true)],
            displayNames: ["h1": "Amina", "h2": "Zoé", "h3": "Bruno", "h5": "Chloé"]
        )
        #expect(checklist.entries.map(\.displayName) == ["Bruno", "Zoé", "Amina", "Chloé"])
        #expect(checklist.missing.map(\.householdId) == ["h3", "h2"])
        #expect(checklist.pickedUp.map(\.householdId) == ["h1", "h5"])
        #expect(checklist.totalCount == 4)
        #expect(checklist.pickedUpCount == 2)
        #expect(checklist.missingCount == 2)
        #expect(checklist.totalShares == 8)
        #expect(checklist.pickedUpShares == 3)
        #expect(checklist.progress == 0.5)
        #expect(!checklist.isComplete)
        #expect(checklist.summary == "2 sur 4 passés · 2 ménages attendus")
    }

    @Test func checklistFallsBackToHouseholdIdForUnknownNames() {
        let checklist = PickupDesk.checklist(shares: [share("h1", 1)])
        #expect(checklist.entries.first?.displayName == "Ménage h1")
        #expect(checklist.summary == "0 sur 1 passés · 1 ménage attendu")
    }

    @Test func checklistProgressBounds() {
        let empty = PickupDesk.checklist(shares: [])
        #expect(empty.progress == 0)
        #expect(!empty.isComplete)
        #expect(empty.summary == "Aucune part à remettre.")

        let done = PickupDesk.checklist(shares: [share("h1", 1, pickedUp: true), share("h2", 2, pickedUp: true)])
        #expect(done.progress == 1)
        #expect(done.isComplete)
        #expect(done.summary == "Tout le monde est passé !")
    }

    @Test func scanningThenRebuildingTheChecklistAdvancesProgress() {
        var current = [share("h1", 1), share("h2", 1)]
        let code = ShareAllocator.qrCode(orderId: "go1", householdId: "h2")
        guard case .pickedUp(let updated) = PickupDesk.scan(code, order: order(), shares: current) else {
            Issue.record("Le scan aurait dû réussir.")
            return
        }
        current = current.map { $0.householdId == updated.householdId ? updated : $0 }
        let checklist = PickupDesk.checklist(shares: current)
        #expect(checklist.progress == 0.5)
        #expect(checklist.missing.map(\.householdId) == ["h1"])
    }

    // MARK: - T-159 : une seule cueillette par ménage

    @Test func memberCodeRecordsWhoPicksUpAndSecondMemberIsRefused() {
        let qr = ShareAllocator.qrCode(orderId: "go1", householdId: "h1")
        let when = Date(timeIntervalSince1970: 5_000)
        let first = PickupDesk.scan(PickupDesk.memberCode(qr, memberId: "amina"), order: order(), shares: shares, at: when)
        #expect(first.isSuccess)
        #expect(first.share?.pickedUpBy == "amina")
        #expect(first.share?.pickedUpAt == when)

        // Le deuxième membre montre le même QR (avec son uid) : refusé, la part reste à Amina.
        var after = shares
        after[0] = first.share!
        let second = PickupDesk.scan(PickupDesk.memberCode(qr, memberId: "karim"), order: order(), shares: after)
        #expect(second == .alreadyPickedUp(first.share!))
        #expect(second.share?.pickedUpBy == "amina")
    }

    @Test func memberCodeSplitsAndOldCodesStillWork() {
        let qr = ShareAllocator.qrCode(orderId: "go1", householdId: "h1")
        #expect(PickupDesk.splitMemberCode("\(qr)#karim") == (qr, "karim"))
        #expect(PickupDesk.splitMemberCode(qr) == (qr, nil))
        #expect(PickupDesk.memberCode(qr, memberId: "") == qr)
        let old = PickupDesk.scan(qr, order: order(), shares: shares)
        #expect(old.isSuccess)
        #expect(old.share?.pickedUpBy == nil)
    }

    @Test func tamperedMemberCodeIsStillUnknown() {
        let qr = ShareAllocator.qrCode(orderId: "go1", householdId: "h1")
        let tampered = qr.replacingOccurrences(of: "h1", with: "h9") + "#karim"
        #expect(PickupDesk.scan(tampered, order: order(), shares: shares) == .unknownCode)
    }

    @Test func fakeRepositoryHandsTheShareOverOnce() async throws {
        let repository = FakeGroupOrderRepository(groupOrders: [order()], shares: ["go1": shares])
        let qr = ShareAllocator.qrCode(orderId: "go1", householdId: "h1")
        let first = try await repository.confirmPickup(code: PickupDesk.memberCode(qr, memberId: "amina"), groupOrderId: "go1", at: .now)
        #expect(first.isSuccess)
        let second = try await repository.confirmPickup(code: PickupDesk.memberCode(qr, memberId: "karim"), groupOrderId: "go1", at: .now)
        #expect(!second.isSuccess)
        let stored = try await repository.shares(ofGroupOrder: "go1").first { $0.householdId == "h1" }
        #expect(stored?.isPickedUp == true)
        #expect(stored?.pickedUpBy == "amina")
    }
}
