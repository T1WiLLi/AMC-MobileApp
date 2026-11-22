import Foundation
import Testing
@testable import AMC_MobileApp

/// T-207 : étape de paiement des organismes (don, parrainage) : succès, refus, réessai, double toucher.
@MainActor
struct OrganizationCheckoutTests {
    private let organizationId = FakeData.ID.laRuche
    private let groupId = FakeData.ID.parcEx

    private func makePortal() async -> (OrganizationPortalModel, FakeOrganizationRepository) {
        let repository = FakeOrganizationRepository()
        let portal = OrganizationPortalModel(repository: repository, organizationId: organizationId)
        await portal.load()
        return (portal, repository)
    }

    private func makeCheckout(
        _ portal: OrganizationPortalModel,
        purpose: OrganizationCheckoutModel.Purpose? = nil,
        amountCents: Cents = 13_000,
        authenticator: any BiometricAuthenticator = FakeBiometricAuthenticator(),
        outcome: PaymentSimulator.Outcome = .success
    ) -> OrganizationCheckoutModel {
        OrganizationCheckoutModel(
            portal: portal,
            purpose: purpose ?? .donation(.suspendedBaskets(count: 5), groupId: groupId),
            amountCents: amountCents,
            groupName: "Parc-Extension",
            authenticator: authenticator,
            simulator: PaymentSimulator(outcome: outcome),
            processingDelay: .zero
        )
    }

    private func donationCount(_ repository: FakeOrganizationRepository) async throws -> Int {
        try await repository.donations(ofOrganization: organizationId).count
    }

    @Test func successfulDonationWritesOneDonationAndShowsReceipt() async throws {
        let (portal, repository) = await makePortal()
        let before = try await donationCount(repository)
        let checkout = makeCheckout(portal)

        await checkout.pay()

        let receipt = try #require(checkout.receipt)
        #expect(try await donationCount(repository) == before + 1)
        let donation = try #require(portal.lastDonation)
        #expect(receipt.amountCents == donation.amountCents)
        #expect(receipt.methodLabel == PaymentSimulator.organizationCardLabel)
        #expect(receipt.methodLabel.hasSuffix("•••• 4242"))
        #expect(receipt.number.hasPrefix("LG-"))
        #expect(!receipt.isRecurring)
        #expect(receipt.purpose == .donation(kind: .suspendedBaskets, basketCount: 5,
                                             householdsReached: donation.householdsReached))
        // L'historique du portail retrouve le même reçu à partir du don.
        #expect(portal.receipt(forDonationId: donation.id) == receipt)
        #expect(portal.recentDonations().first?.id == donation.id)
    }

    @Test func declinedPaymentWritesNothing() async throws {
        let (portal, repository) = await makePortal()
        let before = try await donationCount(repository)
        let checkout = makeCheckout(portal, outcome: .declined)

        await checkout.pay()

        #expect(checkout.phase == .declined(.refusedByIssuer))
        #expect(checkout.receipt == nil)
        #expect(try await donationCount(repository) == before)
    }

    @Test func amountOverCardLimitIsDeclined() async throws {
        let (portal, repository) = await makePortal()
        let before = try await donationCount(repository)
        let checkout = makeCheckout(
            portal, purpose: .donation(.fund(amountCents: 300_000), groupId: groupId), amountCents: 300_000
        )

        await checkout.pay()

        #expect(checkout.phase == .declined(.overCardLimit(limitCents: PaymentSimulator.organizationCardLimitCents)))
        #expect(try await donationCount(repository) == before)
    }

    @Test func retryAfterDeclineSucceedsWithASingleDonation() async throws {
        let (portal, repository) = await makePortal()
        let before = try await donationCount(repository)
        let checkout = makeCheckout(portal, outcome: .declined)

        await checkout.pay()
        #expect(checkout.phase == .declined(.refusedByIssuer))

        checkout.simulator.outcome = .success
        await checkout.pay()

        #expect(checkout.receipt != nil)
        #expect(checkout.attempts == 2)
        #expect(try await donationCount(repository) == before + 1)
    }

    @Test func doubleTapCreatesOneDonation() async throws {
        let (portal, repository) = await makePortal()
        let before = try await donationCount(repository)
        let checkout = makeCheckout(portal)

        async let first: Void = checkout.pay()
        async let second: Void = checkout.pay()
        _ = await (first, second)
        // Un toucher après le succès ne paie pas une deuxième fois.
        await checkout.pay()

        #expect(checkout.receipt != nil)
        #expect(checkout.attempts == 1)
        #expect(try await donationCount(repository) == before + 1)
    }

    @Test func cancelledAuthenticationReturnsToReview() async throws {
        let (portal, repository) = await makePortal()
        let before = try await donationCount(repository)
        let checkout = makeCheckout(
            portal, authenticator: FakeBiometricAuthenticator(result: .failure(.invalidInput("Déverrouillage annulé.")))
        )

        await checkout.pay()

        #expect(checkout.phase == .review)
        #expect(try await donationCount(repository) == before)
    }

    @Test func refusedIdentityShowsAnError() async throws {
        let (portal, repository) = await makePortal()
        let before = try await donationCount(repository)
        let checkout = makeCheckout(portal, authenticator: FakeBiometricAuthenticator(result: .failure(.permissionDenied)))

        await checkout.pay()

        #expect(checkout.phase == .failed(.permissionDenied))
        #expect(try await donationCount(repository) == before)
    }

    /// Simulateur sans Face ID ni code : la touche « Payer » vaut confirmation.
    @Test func deviceWithoutAuthenticationStillPays() async throws {
        let (portal, _) = await makePortal()
        let checkout = makeCheckout(
            portal,
            authenticator: FakeBiometricAuthenticator(kind: .unavailable, result: .failure(.permissionDenied))
        )

        await checkout.pay()

        #expect(checkout.receipt != nil)
    }

    @Test func failedWriteCanBeRetried() async throws {
        let (portal, _) = await makePortal()
        let checkout = makeCheckout(portal, purpose: .donation(.suspendedBaskets(count: 1), groupId: "group-inconnu"))

        await checkout.pay()

        #expect(checkout.phase == .failed(.notFound))
        checkout.backToReview()
        #expect(checkout.phase == .review)
    }

    @Test func sponsorshipShowsMonthlyReceiptWithoutDonation() async throws {
        let (portal, repository) = await makePortal()
        let before = try await donationCount(repository)
        let checkout = makeCheckout(
            portal, purpose: .sponsorship(groupId: FakeData.ID.montrealNord, monthlyBasketGoal: 10), amountCents: 28_000
        )

        await checkout.pay()

        let receipt = try #require(checkout.receipt)
        #expect(receipt.isRecurring)
        #expect(receipt.amountCents == 28_000)
        #expect(receipt.purpose == .sponsorship(monthlyBasketGoal: 10))
        #expect(portal.sponsorship(ofGroup: FakeData.ID.montrealNord)?.monthlyBasketGoal == 10)
        // Un parrainage reste un engagement : aucun don écrit.
        #expect(try await donationCount(repository) == before)
    }

    @Test func receiptNumberIsStableAndReadable() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Montreal")!
        let date = Date(timeIntervalSince1970: 1_795_000_000)
        let firestoreId = OrganizationPaymentReceipt.number(for: "aB3dE5fG7hJ9kL1mN2pQ", date: date, calendar: calendar)
        #expect(firestoreId == OrganizationPaymentReceipt.number(for: "aB3dE5fG7hJ9kL1mN2pQ", date: date, calendar: calendar))
        #expect(firestoreId.hasSuffix("-1MN2PQ"))
        #expect(firestoreId.range(of: #"^LG-\d{8}-[0-9A-Z]{6}$"#, options: .regularExpression) != nil)
        let shortId = OrganizationPaymentReceipt.number(for: "d-1", date: date, calendar: calendar)
        #expect(shortId.range(of: #"^LG-\d{8}-[0-9A-Z]{6}$"#, options: .regularExpression) != nil)
        #expect(shortId != OrganizationPaymentReceipt.number(for: "d-2", date: date, calendar: calendar))
    }

    @Test func cardLimitDecision() {
        let simulator = PaymentSimulator()
        #expect(simulator.authorizeOrganizationCharge(amountCents: PaymentSimulator.organizationCardLimitCents) == nil)
        #expect(simulator.authorizeOrganizationCharge(amountCents: PaymentSimulator.organizationCardLimitCents + 1)
                == .overCardLimit(limitCents: PaymentSimulator.organizationCardLimitCents))
        #expect(PaymentSimulator(outcome: .declined).authorizeOrganizationCharge(amountCents: 100) == .refusedByIssuer)
    }
}
