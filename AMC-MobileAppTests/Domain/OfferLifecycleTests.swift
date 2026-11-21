import Foundation
import Testing
@testable import AMC_MobileApp

/// Tests de OfferLifecycle (E04 : RQ-036 à RQ-038).
struct OfferLifecycleTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let day: TimeInterval = 24 * 3600

    static func offer(status: Offer.Status = .active) -> Offer {
        Offer(
            id: "o1", vendorId: "v1", productId: "p1", totalShares: 40, shareUnit: "10 kg",
            tiers: [
                PriceTier(minShares: 10, priceCents: 1_150),
                PriceTier(minShares: 20, priceCents: 990),
                PriceTier(minShares: 30, priceCents: 850),
            ],
            minimumSharesToLaunch: 10, deadline: now.addingTimeInterval(3 * day), zones: ["z1", "z2"],
            status: status
        )
    }

    static func order(_ id: String, offerId: String = "o1", status: GroupOrder.Status) -> GroupOrder {
        GroupOrder(id: id, groupId: "g1", offerId: offerId, status: status, currentTierIndex: nil,
                   committedShares: 0, committedHouseholds: 0, pickupPointId: nil, pickupSlots: [])
    }

    static func message(_ body: () throws -> Void) -> String? {
        do {
            try body()
            return nil
        } catch let error as AppError {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    // MARK: Validation

    @Test func validOfferPasses() throws {
        try OfferLifecycle.validate(Self.offer(), now: Self.now)
    }

    @Test func unsortedButCoherentTiersPass() throws {
        var offer = Self.offer()
        offer.tiers.reverse()
        try OfferLifecycle.validate(offer, now: Self.now)
    }

    @Test func validationRejectsIncoherentOffers() {
        var priceUp = Self.offer()
        priceUp.tiers[1].priceCents = 1_200
        #expect(Self.message { try OfferLifecycle.validate(priceUp, now: Self.now) }?
            .hasPrefix("Le prix du palier 2 doit être plus bas") == true)

        var duplicateThreshold = Self.offer()
        duplicateThreshold.tiers[1].minShares = 10
        #expect(Self.message { try OfferLifecycle.validate(duplicateThreshold, now: Self.now) } != nil)

        var tooHigh = Self.offer()
        tooHigh.minimumSharesToLaunch = 41
        #expect(Self.message { try OfferLifecycle.validate(tooHigh, now: Self.now) } != nil)

        var tierAboveTotal = Self.offer()
        tierAboveTotal.totalShares = 25
        #expect(Self.message { try OfferLifecycle.validate(tierAboveTotal, now: Self.now) }?
            .contains("dépasse le total") == true)

        var noTiers = Self.offer()
        noTiers.tiers = []
        #expect(Self.message { try OfferLifecycle.validate(noTiers, now: Self.now) } == "Ajoute au moins un palier de prix.")

        var past = Self.offer()
        past.deadline = Self.now
        #expect(Self.message { try OfferLifecycle.validate(past, now: Self.now) } == "La date limite doit être dans le futur.")

        var free = Self.offer()
        free.tiers[2].priceCents = 0
        #expect(Self.message { try OfferLifecycle.validate(free, now: Self.now) } != nil)
    }

    // MARK: RQ-036 modifier

    @Test func anythingGoesWithoutCommittedShares() throws {
        var proposed = Self.offer()
        proposed.tiers = [PriceTier(minShares: 5, priceCents: 1_500), PriceTier(minShares: 15, priceCents: 1_200)]
        proposed.totalShares = 20
        proposed.minimumSharesToLaunch = 5
        proposed.deadline = Self.now.addingTimeInterval(Self.day)
        proposed.zones = ["z3"]
        proposed.shareUnit = "5 kg"
        let edited = try OfferLifecycle.edited(Self.offer(), to: proposed, committedShares: 0, now: Self.now)
        #expect(edited == proposed)
    }

    @Test func editKeepsTheOriginalStatus() throws {
        var proposed = Self.offer(status: .cancelled)
        proposed.totalShares = 45
        let edited = try OfferLifecycle.edited(Self.offer(), to: proposed, committedShares: 12, now: Self.now)
        #expect(edited.status == .active)
        #expect(edited.totalShares == 45)
    }

    @Test func committedSharesAllowBetterPricesAndLongerDeadline() throws {
        var proposed = Self.offer()
        proposed.tiers = [
            PriceTier(minShares: 10, priceCents: 1_100),
            PriceTier(minShares: 18, priceCents: 990),
            PriceTier(minShares: 30, priceCents: 800),
        ]
        proposed.deadline = Self.offer().deadline.addingTimeInterval(Self.day)
        proposed.zones = ["z1", "z2", "z3"]
        proposed.minimumSharesToLaunch = 8
        let edited = try OfferLifecycle.edited(Self.offer(), to: proposed, committedShares: 15, now: Self.now)
        #expect(edited.tiers == proposed.tiers)
    }

    @Test func committedSharesForbidRaisingAPrice() {
        var proposed = Self.offer()
        proposed.tiers[2].priceCents = 900
        #expect(Self.message { _ = try OfferLifecycle.edited(Self.offer(), to: proposed, committedShares: 1, now: Self.now) }?
            .contains("tu ne peux pas augmenter un prix") == true)

        // Déplacer un seuil plus haut rend la part plus chère entre 20 et 24 parts.
        var moved = Self.offer()
        moved.tiers[1].minShares = 25
        #expect(Self.message { _ = try OfferLifecycle.edited(Self.offer(), to: moved, committedShares: 1, now: Self.now) } != nil)
    }

    @Test func committedSharesForbidShrinkingBelowCommitted() throws {
        var proposed = Self.offer()
        proposed.totalShares = 30
        _ = try OfferLifecycle.edited(Self.offer(), to: proposed, committedShares: 30, now: Self.now)
        #expect(Self.message { _ = try OfferLifecycle.edited(Self.offer(), to: proposed, committedShares: 31, now: Self.now) }
            == "Des voisins ont déjà engagé 31 parts : le lot doit en compter au moins autant.")
    }

    @Test func committedSharesOnlyAllowExtendingTheDeadline() {
        var proposed = Self.offer()
        proposed.deadline = Self.offer().deadline.addingTimeInterval(-3600)
        #expect(Self.message { _ = try OfferLifecycle.edited(Self.offer(), to: proposed, committedShares: 5, now: Self.now) }
            == "Des parts sont déjà engagées : tu peux seulement repousser la date limite.")
    }

    @Test func committedSharesForbidOtherBreakingChanges() {
        var unit = Self.offer()
        unit.shareUnit = "5 kg"
        var minimum = Self.offer()
        minimum.minimumSharesToLaunch = 12
        var zones = Self.offer()
        zones.zones = ["z1"]
        for proposed in [unit, minimum, zones] {
            #expect(Self.message { _ = try OfferLifecycle.edited(Self.offer(), to: proposed, committedShares: 5, now: Self.now) } != nil)
        }
    }

    @Test func cannotEditAClosedOfferOrChangeItsProduct() {
        #expect(Self.message { _ = try OfferLifecycle.edited(Self.offer(status: .closed), to: Self.offer(), committedShares: 0, now: Self.now) }
            == "Ce lot est clôturé : tu ne peux plus le modifier.")
        var other = Self.offer()
        other.productId = "p2"
        #expect(Self.message { _ = try OfferLifecycle.edited(Self.offer(), to: other, committedShares: 0, now: Self.now) } != nil)
    }

    // MARK: RQ-036 pause

    @Test func pauseHidesTheOfferAndResumeExtendsTheDeadline() throws {
        let paused = try OfferLifecycle.pause(Self.offer(), now: Self.now)
        #expect(paused.storedOffer.status == .draft)
        #expect(paused.original.status == .active)

        let resumed = try OfferLifecycle.resume(paused, now: Self.now.addingTimeInterval(Self.day))
        #expect(resumed.status == .active)
        #expect(resumed.deadline == Self.offer().deadline.addingTimeInterval(Self.day))
    }

    @Test func onlyAnActiveOfferCanBePaused() {
        for status in [Offer.Status.draft, .closed, .cancelled] {
            #expect(Self.message { _ = try OfferLifecycle.pause(Self.offer(status: status), now: Self.now) }
                == "Seul un lot publié peut être mis en pause.")
        }
        #expect(Self.message { _ = try OfferLifecycle.pause(Self.offer(), now: Self.offer().deadline) } != nil)
    }

    @Test func resumeBeforePauseThrows() throws {
        let paused = try OfferLifecycle.pause(Self.offer(), now: Self.now)
        #expect(Self.message { _ = try OfferLifecycle.resume(paused, now: Self.now.addingTimeInterval(-1)) } != nil)
    }

    // MARK: RQ-036 retrait

    @Test func withdrawCancelsTheOfferAndItsOpenOrders() throws {
        let orders = [
            Self.order("a", status: .open),
            Self.order("b", status: .reached),
            Self.order("c", status: .closed),
            Self.order("d", status: .delivered),
            Self.order("e", offerId: "o2", status: .open),
        ]
        let withdrawal = try OfferLifecycle.withdraw(Self.offer(), orders: orders)
        #expect(withdrawal.offer.status == .cancelled)
        #expect(withdrawal.cancelledOrders.map(\.id) == ["a", "b"])
        #expect(withdrawal.cancelledOrders.allSatisfy { $0.status == .cancelled })
    }

    @Test func withdrawingTwiceThrows() {
        #expect(Self.message { _ = try OfferLifecycle.withdraw(Self.offer(status: .cancelled), orders: []) }
            == "Ce lot est retiré : tu ne peux plus le retirer.")
        #expect(Self.message { _ = try OfferLifecycle.withdraw(Self.offer(status: .closed), orders: []) } != nil)
    }

    // MARK: RQ-037 dupliquer

    @Test func duplicateKeepsProductTiersZonesAndShiftsTheDeadline() throws {
        var source = Self.offer(status: .closed)
        source.deadline = Self.now.addingTimeInterval(-Self.day)
        let copy = try OfferLifecycle.duplicate(source, now: Self.now) { "o2" }
        #expect(copy.id == "o2")
        #expect(copy.status == .draft)
        #expect(copy.productId == source.productId)
        #expect(copy.tiers == source.tiers)
        #expect(copy.zones == source.zones)
        #expect(copy.totalShares == source.totalShares)
        #expect(copy.deadline == Self.now.addingTimeInterval(7 * Self.day))
    }

    @Test func duplicateCanBePublishedWithACustomInterval() throws {
        let copy = try OfferLifecycle.duplicate(Self.offer(), status: .active, interval: 14 * Self.day, now: Self.now) { "o3" }
        #expect(copy.status == .active)
        #expect(copy.deadline == Self.now.addingTimeInterval(14 * Self.day))
    }

    @Test func duplicateRejectsBadStatusOrSameId() {
        #expect(Self.message { _ = try OfferLifecycle.duplicate(Self.offer(), status: .closed, now: Self.now) { "o2" } } != nil)
        #expect(Self.message { _ = try OfferLifecycle.duplicate(Self.offer(), now: Self.now) { "o1" } } != nil)
    }

    // MARK: RQ-038 invendus

    @Test func leftoversOfferDiscountsTiersAndShortensTheDeadline() throws {
        let leftovers = try OfferLifecycle.leftoversOffer(from: Self.offer(status: .closed), leftoverShares: 25, now: Self.now) { "inv1" }
        #expect(leftovers.id == "inv1")
        #expect(leftovers.status == .active)
        #expect(leftovers.totalShares == 25)
        // 30 % de rabais ; le palier de 30 parts est ramené à 25 (toutes les parts restantes).
        #expect(leftovers.tiers == [
            PriceTier(minShares: 10, priceCents: 805),
            PriceTier(minShares: 20, priceCents: 693),
            PriceTier(minShares: 25, priceCents: 595),
        ])
        #expect(leftovers.minimumSharesToLaunch == 10)
        #expect(leftovers.deadline == Self.now.addingTimeInterval(48 * 3600))
        #expect(leftovers.productId == "p1")
        #expect(leftovers.zones == ["z1", "z2"])
    }

    @Test func fewLeftoversCollapseTiersAndLowerTheMinimum() throws {
        let leftovers = try OfferLifecycle.leftoversOffer(
            from: Self.offer(), leftoverShares: 4, discountPercent: 50, duration: Self.day, now: Self.now
        ) { "inv2" }
        #expect(leftovers.tiers == [PriceTier(minShares: 4, priceCents: 425)])
        #expect(leftovers.minimumSharesToLaunch == 4)
        #expect(leftovers.deadline == Self.now.addingTimeInterval(Self.day))
    }

    @Test func leftoversWorkWithAnAllocation() throws {
        let shares = [
            Share(householdId: "h1", quantity: 12, finalPriceCents: nil, isPaid: false,
                  suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false),
        ]
        let allocation = try ShareAllocator.allocate(orderId: "go1", offer: Self.offer(), shares: shares, unitPriceCents: 1_150)
        let leftovers = try OfferLifecycle.leftoversOffer(
            from: Self.offer(), leftoverShares: allocation.unallocatedShares, now: Self.now
        ) { "inv3" }
        #expect(leftovers.totalShares == 28)
        try OfferLifecycle.validate(leftovers, now: Self.now)
    }

    @Test func roundedPricesStayStrictlyDecreasingAndPositive() throws {
        var cheap = Self.offer()
        cheap.tiers = [PriceTier(minShares: 1, priceCents: 3), PriceTier(minShares: 2, priceCents: 2), PriceTier(minShares: 3, priceCents: 1)]
        cheap.minimumSharesToLaunch = 1
        let leftovers = try OfferLifecycle.leftoversOffer(from: cheap, leftoverShares: 3, discountPercent: 90, now: Self.now) { "inv4" }
        #expect(leftovers.tiers == [PriceTier(minShares: 1, priceCents: 1)])
        #expect(leftovers.tiers.allSatisfy { $0.priceCents > 0 })
    }

    @Test func discountRoundsToTheCent() {
        #expect(OfferLifecycle.discounted(1_150, percent: 30) == 805)
        #expect(OfferLifecycle.discounted(999, percent: 30) == 699) // 699,3
        #expect(OfferLifecycle.discounted(995, percent: 30) == 697) // 696,5 → 697
        #expect(OfferLifecycle.discounted(1, percent: 99) == 1)
        #expect(OfferLifecycle.discounted(1_000, percent: 0) == 1_000)
    }

    @Test func leftoversRejectBadInput() {
        #expect(Self.message { _ = try OfferLifecycle.leftoversOffer(from: Self.offer(), leftoverShares: 0, now: Self.now) { "x" } }
            == "Il ne reste aucune part à écouler.")
        #expect(Self.message { _ = try OfferLifecycle.leftoversOffer(from: Self.offer(), leftoverShares: 41, now: Self.now) { "x" } } != nil)
        #expect(Self.message { _ = try OfferLifecycle.leftoversOffer(from: Self.offer(), leftoverShares: 5, discountPercent: 100, now: Self.now) { "x" } } != nil)
        #expect(Self.message { _ = try OfferLifecycle.leftoversOffer(from: Self.offer(), leftoverShares: 5, now: Self.now) { "o1" } } != nil)
    }
}
