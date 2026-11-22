import Foundation
import Testing
@testable import AMC_MobileApp

/// Tests de PickupDesk (RQ-066, RQ-067) et du code de cueillette à jeton privé (sécurité).
struct PickupDeskTests {
    private func order(_ status: GroupOrder.Status = .delivered, id: String = "go1") -> GroupOrder {
        var order = TierEngineTests.order(committed: 5, status: status)
        order.id = id
        return order
    }

    private func share(_ household: String, _ quantity: Int, pickedUp: Bool = false) -> Share {
        var share = TierEngineTests.share(household, quantity)
        share.isPickedUp = pickedUp
        return share
    }

    private var shares: [Share] { [share("h1", 2), share("h2", 3, pickedUp: true), share("h3", 0)] }

    /// Jetons privés des ménages (`shares/{h}/private/pickup`).
    private let tokens = ["h1": "0123456789abcdef0123456789abcdef", "h2": "fedcba9876543210fedcba9876543210",
                          "h3": "00000000000000000000000000000003"]

    private func code(_ household: String, order orderId: String = "go1") -> String {
        PickupDesk.pickupCode(orderId: orderId, householdId: household, token: tokens[household] ?? String(repeating: "9", count: 32))
    }

    private func scan(_ code: String, _ order: GroupOrder? = nil, shares: [Share]? = nil, at date: Date = .now) -> PickupDesk.ScanResult {
        PickupDesk.scan(code, order: order ?? self.order(), shares: shares ?? self.shares, pickupTokens: tokens, at: date)
    }

    /// Ancien code (FNV-1a 32 bits de « commande|ménage ») : n'importe quel membre du groupe le recalcule.
    private func legacyCode(orderId: String, householdId: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in "\(orderId)|\(householdId)".utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return "GRENIER:\(orderId):\(householdId):\(String(format: "%08x", hash))"
    }

    // MARK: - RQ-066

    @Test func validCodeMarksTheSharePickedUp() {
        let result = scan(PickupDesk.memberCode(code("h1"), memberId: "amina"))
        #expect(result.isSuccess)
        #expect(result.share?.householdId == "h1")
        #expect(result.share?.isPickedUp == true)
        #expect(result.message.contains("2 parts"))
    }

    @Test func surroundingWhitespaceIsIgnored() {
        #expect(scan(" \(code("h1"))\n").isSuccess)
    }

    /// Fermée = en route : la part ne se remet qu'une fois la livraison marquée comme arrivée.
    @Test func closedOrderIsNotPickableUntilArrived() {
        #expect(scan(code("h1"), order(.closed)) == .orderNotReady(.closed))
    }

    @Test func alreadyPickedUpShareIsNotGivenTwice() {
        let result = scan(code("h2"))
        #expect(result == .alreadyPickedUp(shares[1]))
        #expect(!result.isSuccess)
    }

    @Test func tamperedOrGarbageCodesAreUnknown() {
        let valid = code("h1")
        let otherHousehold = valid.replacingOccurrences(of: ":h1:", with: ":h2:")
        let flipped = String(valid.dropLast()) + "0"
        for code in ["", "hello", otherHousehold, flipped, "GRENIER:go1:h1:", "GRENIER:go1:h1:\(String(repeating: "0", count: 32))",
                     "GRENIER:go1:h1/x:\(tokens["h1"]!)", "GRENIER:go1:h1:\(tokens["h1"]!.uppercased())"] {
            #expect(scan(code) == .unknownCode, "\(code)")
        }
    }

    /// Sécurité : sans le jeton, un code bien formé avec les ids publics de la commande et du ménage ne passe pas.
    @Test func codeRebuiltFromPublicIdsIsRefused() {
        #expect(scan(legacyCode(orderId: "go1", householdId: "h1")) == .outdatedCode)
        #expect(scan(PickupDesk.memberCode(legacyCode(orderId: "go1", householdId: "h1"), memberId: "intrus")) == .outdatedCode)
        #expect(!PickupDesk.ScanResult.outdatedCode.message.isEmpty)
        #expect(PickupDesk.ScanResult.outdatedCode.share == nil)
    }

    @Test func householdWithoutTokenOrShareIsUnknown() {
        // h1 n'a pas encore ouvert son code : aucun jeton, aucun code ne passe.
        let result = PickupDesk.scan(code("h1"), order: order(), shares: shares, pickupTokens: [:])
        #expect(result == .unknownCode)
        #expect(scan(code("h4")) == .unknownCode)
        #expect(scan(code("h3")) == .unknownCode)
    }

    @Test func codeOfAnotherOrderIsWrongOrder() {
        let result = scan(code("h1", order: "go2"))
        #expect(result == .wrongOrder)
        #expect(result.message.contains("autre commande"))
    }

    @Test func onlyDeliveredOrdersCanBePickedUp() {
        for status in [GroupOrder.Status.open, .reached, .closed, .cancelled] {
            let result = scan(code("h1"), order(status))
            #expect(result == .orderNotReady(status))
            #expect(!result.message.isEmpty)
            #expect(PickupDesk.handOver(householdId: "h1", order: order(status), shares: shares, pickedUpBy: "hote") == .orderNotReady(status))
        }
        #expect(GroupOrder.Status.allCases.filter(PickupDesk.canPickUp) == [.delivered])
    }

    // MARK: - Jeton

    @Test func newTokensAreWellFormedAndUnique() {
        let generated = (0..<200).map { _ in PickupDesk.newPickupToken() }
        #expect(generated.allSatisfy(PickupDesk.isPickupToken))
        #expect(Set(generated).count == generated.count)
        #expect(!PickupDesk.isPickupToken("abc"))
        #expect(!PickupDesk.isPickupToken(String(repeating: "g", count: 32)))
        #expect(!PickupDesk.isPickupToken(String(repeating: "A", count: 32)))
    }

    @Test func codeParsesIntoOrderHouseholdTokenAndMember() {
        let parsed = PickupDesk.parse(PickupDesk.memberCode(code("h1"), memberId: "karim"))
        #expect(parsed == PickupDesk.ParsedCode(orderId: "go1", householdId: "h1", secret: tokens["h1"]!, memberId: "karim"))
        #expect(parsed?.isLegacy == false)
        #expect(PickupDesk.parse(legacyCode(orderId: "go1", householdId: "h1"))?.isLegacy == true)
        #expect(PickupDesk.parse("grenier://part/h1") == nil)
        #expect(code("h1").hasPrefix(ShareAllocator.qrCodePrefix))
    }

    // MARK: - Remise à la main (« Récupéré »)

    @Test func handOverRecordsWhoConfirmedAndOnlyOnce() {
        let when = Date(timeIntervalSince1970: 9_000)
        let result = PickupDesk.handOver(householdId: "h1", order: order(), shares: shares, pickedUpBy: "hote", at: when)
        #expect(result.isSuccess)
        #expect(result.share?.pickedUpBy == "hote")
        #expect(result.share?.pickedUpAt == when)
        #expect(PickupDesk.handOver(householdId: "h2", order: order(), shares: shares, pickedUpBy: "hote") == .alreadyPickedUp(shares[1]))
        #expect(PickupDesk.handOver(householdId: "h9", order: order(), shares: shares, pickedUpBy: "hote") == .unknownCode)
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
        guard case .pickedUp(let updated) = scan(code("h2"), shares: current) else {
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
        let qr = code("h1")
        let when = Date(timeIntervalSince1970: 5_000)
        let first = scan(PickupDesk.memberCode(qr, memberId: "amina"), at: when)
        #expect(first.isSuccess)
        #expect(first.share?.pickedUpBy == "amina")
        #expect(first.share?.pickedUpAt == when)

        // Le deuxième membre montre le même QR (avec son uid) : refusé, la part reste à Amina.
        var after = shares
        after[0] = first.share!
        let second = scan(PickupDesk.memberCode(qr, memberId: "karim"), shares: after)
        #expect(second == .alreadyPickedUp(first.share!))
        #expect(second.share?.pickedUpBy == "amina")
    }

    @Test func memberCodeSplits() {
        let qr = code("h1")
        #expect(PickupDesk.splitMemberCode("\(qr)#karim") == (qr, "karim"))
        #expect(PickupDesk.splitMemberCode(qr) == (qr, nil))
        #expect(PickupDesk.memberCode(qr, memberId: "") == qr)
        let withoutMember = scan(qr)
        #expect(withoutMember.isSuccess)
        #expect(withoutMember.share?.pickedUpBy == nil)
    }

    @Test func tamperedMemberCodeIsStillUnknown() {
        let tampered = code("h1").replacingOccurrences(of: ":h1:", with: ":h9:") + "#karim"
        #expect(scan(tampered) == .unknownCode)
    }

    @Test func fakeRepositoryHandsTheShareOverOnce() async throws {
        let repository = FakeGroupOrderRepository(groupOrders: [order()], shares: ["go1": shares])
        let qr = try await repository.pickupCode(householdId: "h1", groupOrderId: "go1")
        #expect(try await repository.pickupCode(householdId: "h1", groupOrderId: "go1") == qr)
        let first = try await repository.confirmPickup(code: PickupDesk.memberCode(qr, memberId: "amina"), groupOrderId: "go1", at: .now)
        #expect(first.isSuccess)
        let second = try await repository.confirmPickup(code: PickupDesk.memberCode(qr, memberId: "karim"), groupOrderId: "go1", at: .now)
        #expect(!second.isSuccess)
        let stored = try await repository.shares(ofGroupOrder: "go1").first { $0.householdId == "h1" }
        #expect(stored?.isPickedUp == true)
        #expect(stored?.pickedUpBy == "amina")
    }

    @Test func fakeRepositoryRefusesCodesWithoutTheHouseholdToken() async throws {
        let repository = FakeGroupOrderRepository(groupOrders: [order()], shares: ["go1": shares])
        _ = try await repository.pickupCode(householdId: "h1", groupOrderId: "go1")
        let forged = PickupDesk.memberCode(PickupDesk.pickupCode(orderId: "go1", householdId: "h1", token: PickupDesk.newPickupToken()),
                                           memberId: "intrus")
        #expect(try await repository.confirmPickup(code: forged, groupOrderId: "go1", at: .now) == .unknownCode)
        #expect(try await repository.confirmPickup(code: legacyCode(orderId: "go1", householdId: "h1"), groupOrderId: "go1", at: .now) == .outdatedCode)
        let stored = try await repository.shares(ofGroupOrder: "go1").first { $0.householdId == "h1" }
        #expect(stored?.isPickedUp == false)
        await #expect(throws: AppError.notFound) { try await repository.pickupCode(householdId: "h9", groupOrderId: "go1") }
    }

    @Test func fakeRepositoryConfirmsByHandWithoutAnyToken() async throws {
        let repository = FakeGroupOrderRepository(groupOrders: [order()], shares: ["go1": shares])
        let result = try await repository.confirmPickupByHand(householdId: "h1", groupOrderId: "go1", confirmedBy: "hote", at: .now)
        #expect(result.isSuccess)
        let stored = try await repository.shares(ofGroupOrder: "go1").first { $0.householdId == "h1" }
        #expect(stored?.pickedUpBy == "hote")
        #expect(try await repository.confirmPickupByHand(householdId: "h1", groupOrderId: "go1", confirmedBy: "hote", at: .now) == .alreadyPickedUp(stored!))
    }

    // MARK: QR d'un groupe (T-198)

    @Test func groupCodeBundlesEachOrderCode() {
        let c1 = PickupDesk.pickupCode(orderId: "go1", householdId: "h1", token: PickupDesk.newPickupToken())
        let c2 = PickupDesk.pickupCode(orderId: "go2", householdId: "h1", token: PickupDesk.newPickupToken())
        let bundle = PickupDesk.bundleCode([PickupDesk.memberCode(c1, memberId: "amina"), PickupDesk.memberCode(c2, memberId: "amina")])
        #expect(bundle == "\(c1)|\(c2)#amina")
        #expect(PickupDesk.bundledCodes(bundle ?? "") == ["\(c1)#amina", "\(c2)#amina"])
        #expect(PickupDesk.code(for: "go2", in: bundle ?? "") == "\(c2)#amina")
        // Un code de commande seul reste lui-même ; une commande absente du QR → son premier code (mauvaise commande).
        #expect(PickupDesk.bundledCodes(c1) == [c1])
        #expect(PickupDesk.code(for: "go9", in: bundle ?? "") == "\(c1)#amina")
        #expect(PickupDesk.bundleCode([]) == nil)
    }

    @Test func scanningAGroupCodeHandsOverOnlyThisOrder() {
        let bundle = PickupDesk.bundleCode([
            PickupDesk.pickupCode(orderId: "autre", householdId: "h1", token: PickupDesk.newPickupToken()),
            code("h1"),
        ]).map { PickupDesk.memberCode($0, memberId: "amina") } ?? ""
        let result = scan(bundle)
        #expect(result.isSuccess)
        #expect(result.share?.pickedUpBy == "amina")
    }
}
