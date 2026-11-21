import Testing
@testable import AMC_MobileApp

@MainActor
struct SolidarityParseAmountTests {
    @Test(arguments: [
        ("", 0), ("  ", 0), ("3", 300), ("3,5", 350), ("3,50", 350), ("3.05", 305),
        ("4 $", 400), ("4\u{00A0}$", 400), (",75", 75), ("12,", 1_200), ("100", 10_000), ("0", 0)
    ])
    func acceptsValidAmounts(text: String, cents: Int) {
        #expect(SolidarityMath.parseAmount(text) == .success(cents))
    }

    @Test(arguments: ["-3", "−2,50", "-0"])
    func refusesNegativeAmounts(text: String) throws {
        let error = try #require(failure(text))
        #expect(error.message.contains("négatif"))
    }

    @Test(arguments: ["abc", "3a", "1,2,3", ".", ",", "2e3", "€5"])
    func refusesNonNumericInput(text: String) throws {
        let error = try #require(failure(text))
        #expect(error.message.contains("chiffres"))
    }

    @Test(arguments: ["100,01", "250", "99999999999999999999"])
    func refusesTooLargeAmounts(text: String) throws {
        let error = try #require(failure(text))
        #expect(error.message.contains("maximum"))
    }

    @Test func refusesMoreThanTwoDecimals() throws {
        let error = try #require(failure("3,555"))
        #expect(error.message.contains("deux chiffres"))
    }

    private func failure(_ text: String) -> AppError? {
        if case .failure(let error) = SolidarityMath.parseAmount(text) { error } else { nil }
    }
}

@MainActor
struct SolidarityAllocationTests {
    @Test func splitsEqually() {
        let result = SolidarityMath.allocate(fundCents: 3_000, dues: ["a": 2_600, "b": 2_600])
        #expect(result.subsidies == ["a": 1_500, "b": 1_500])
        #expect(result.remainingCents == 0)
    }

    @Test func neverGivesMoreThanWhatIsDue() {
        let result = SolidarityMath.allocate(fundCents: 6_000, dues: ["a": 500, "b": 2_600, "c": 2_600])
        #expect(result.subsidies == ["a": 500, "b": 2_600, "c": 2_600])
        #expect(result.remainingCents == 300)
    }

    @Test func redistributesWhatACappedHouseholdCannotAbsorb() {
        let result = SolidarityMath.allocate(fundCents: 3_000, dues: ["a": 500, "b": 2_600, "c": 2_600])
        #expect(result.subsidies == ["a": 500, "b": 1_250, "c": 1_250])
        #expect(result.remainingCents == 0)
    }

    @Test func spreadsLeftoverCentsDeterministically() {
        let result = SolidarityMath.allocate(fundCents: 100, dues: ["c": 1_000, "a": 1_000, "b": 1_000])
        #expect(result.subsidies == ["a": 34, "b": 33, "c": 33])
        #expect(result.totalCents == 100)
    }

    @Test func neverNegative() {
        let negativeFund = SolidarityMath.allocate(fundCents: -500, dues: ["a": 1_000])
        #expect(negativeFund.subsidies == ["a": 0])
        #expect(negativeFund.remainingCents == 0)

        let negativeDue = SolidarityMath.allocate(fundCents: 500, dues: ["a": -1_000, "b": 300])
        #expect(negativeDue.subsidies == ["a": 0, "b": 300])
        #expect(negativeDue.remainingCents == 200)
    }

    @Test func emptyEligibleListKeepsTheFund() {
        let result = SolidarityMath.allocate(fundCents: 1_234, dues: [:])
        #expect(result.subsidies.isEmpty)
        #expect(result.remainingCents == 1_234)
    }

    @Test(arguments: [0, 1, 7, 999, 5_000, 100_003])
    func totalNeverExceedsFundNorDues(fund: Int) {
        let dues = ["a": 1_299, "b": 7, "c": 2_600, "d": 0, "e": 455]
        let result = SolidarityMath.allocate(fundCents: fund, dues: dues)
        #expect(result.totalCents + result.remainingCents == fund)
        for (id, given) in result.subsidies {
            #expect(given >= 0)
            #expect(given <= max(0, dues[id] ?? 0))
        }
    }

    @Test func applyingSetsSubsidiesOnEligibleSharesOnly() {
        let shares = [share("amina", quantity: 10), share("h2", quantity: 5), share("h3", quantity: 10, subsidy: 999)]
        let (updated, allocation) = SolidarityMath.applying(
            fundCents: 1_000, to: shares, eligible: ["h2", "h3"], unitPriceCents: 260
        )
        #expect(updated.map(\.subsidyCents) == [0, 500, 500])
        #expect(allocation.remainingCents == 0)
    }

    private func share(_ id: String, quantity: Int, subsidy: Int = 0) -> Share {
        Share(householdId: id, quantity: quantity, finalPriceCents: nil, isPaid: false,
              suspendedAmountCents: 0, subsidyCents: subsidy, qrCode: nil, isPickedUp: false)
    }
}

@MainActor
struct SolidarityFundMathTests {
    @Test func contributionsIgnoreNegativeAmounts() {
        let shares = [500, 200, -300, 0].enumerated().map { index, cents in
            Share(householdId: "h\(index)", quantity: 1, finalPriceCents: nil, isPaid: true,
                  suspendedAmountCents: cents, subsidyCents: 0, qrCode: nil, isPickedUp: false)
        }
        #expect(SolidarityMath.contributions(of: shares) == 700)
    }

    @Test func balanceNeverNegative() {
        #expect(SolidarityMath.balance(contributedCents: 5_000, spentCents: 1_200) == 3_800)
        #expect(SolidarityMath.balance(contributedCents: 1_000, spentCents: 4_000) == 0)
        #expect(SolidarityMath.balance(contributedCents: -10, spentCents: -10) == 0)
    }

    @Test func basketsCovered() {
        #expect(SolidarityMath.basketsCovered(balanceCents: 8_400, basketCostCents: 2_600) == 3)
        #expect(SolidarityMath.basketsCovered(balanceCents: 8_400, basketCostCents: 0) == 0)
        #expect(SolidarityMath.basketsCovered(balanceCents: -100, basketCostCents: 2_600) == 0)
    }

    @Test func amountToPayNeverNegative() {
        #expect(SolidarityMath.amountToPay(dueCents: 2_600, subsidyCents: 800, suspendedCents: 500) == 2_300)
        #expect(SolidarityMath.amountToPay(dueCents: 2_600, subsidyCents: 9_000, suspendedCents: 0) == 0)
        #expect(SolidarityMath.amountToPay(dueCents: 2_600, subsidyCents: -5, suspendedCents: -5) == 2_600)
    }

    @Test func amountDueUsesFinalPriceWhenFrozen() {
        let open = Share(householdId: "a", quantity: 10, finalPriceCents: nil, isPaid: false,
                         suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false)
        var closed = open
        closed.finalPriceCents = 10 * 210  // total figé de la part
        #expect(SolidarityMath.amountDue(of: open, unitPriceCents: 260) == 2_600)
        #expect(SolidarityMath.amountDue(of: closed, unitPriceCents: 260) == 2_100)
    }
}

@MainActor
struct SolidarityTextTests {
    @Test func basketsSentenceNeverNamesAHousehold() {
        #expect(SolidarityFundCard.basketsSentence(count: 12, groupName: "Parc-Ex Ouest") == "12 paniers suspendus offerts à Parc-Ex Ouest ce mois-ci")
        #expect(SolidarityFundCard.basketsSentence(count: 1, groupName: "Parc-Ex Ouest").hasPrefix("1 panier suspendu offert"))
        #expect(SolidarityFundCard.basketsSentence(count: 0, groupName: "Parc-Ex Ouest").hasPrefix("Aucun panier"))
    }

    @Test func editableTextRoundTrips() {
        #expect(SuspendedBasketPicker.editableText(350) == "3,50")
        #expect(SuspendedBasketPicker.editableText(1_200) == "12")
        #expect(SolidarityMath.parseAmount(SuspendedBasketPicker.editableText(1_205)) == .success(1_205))
    }

    @Test func bannerMentionsTheAmountOnly() {
        let banner = SupportedHouseholdBanner(subsidyCents: 800)
        #expect(banner.detailText.contains("8,00"))
    }
}
