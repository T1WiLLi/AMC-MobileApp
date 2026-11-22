import Foundation
import Testing
@testable import AMC_MobileApp

/// T-185 : adresses vérifiées par Apple Maps. Règles pures (`AddressMatching`) et état du champ
/// (`AddressFieldModel`) avec le validateur fake, sans réseau.
@MainActor
struct AddressValidationTests {
    // MARK: Règles

    @Test func civicNumberIsReadAtTheStart() {
        #expect(AddressMatching.civicNumber(in: "7420 rue Ogilvy") == "7420")
        #expect(AddressMatching.civicNumber(in: " 1234A rue Jarry") == "1234a")
        #expect(AddressMatching.civicNumber(in: "8421, rue Pie-IX") == "8421")
        #expect(AddressMatching.civicNumber(in: "rue Jarry Est") == nil)
    }

    @Test func resultMustHaveSameNumberAndSimilarStreet() {
        #expect(AddressMatching.matches(input: "7420 Ogilvy", candidateStreetLine: "7420 Rue Ogilvie"))
        #expect(AddressMatching.matches(input: "8150 boul. Pie-IX, Montréal", candidateStreetLine: "8150 Boulevard Pie-IX"))
        #expect(!AddressMatching.matches(input: "99999 rue Jarry", candidateStreetLine: "Rue Jarry E"), "rue seulement")
        #expect(!AddressMatching.matches(input: "1234 rue Jarry", candidateStreetLine: "1236 Rue Jarry E"))
        #expect(!AddressMatching.matches(input: "1234 rue Jarry", candidateStreetLine: "1234 Rue Jeanne-Mance"))
        #expect(AddressMatching.matches(input: "1234a rue Jarry", candidateStreetLine: "1234 Rue Jarry E"))
    }

    @Test func apartmentAndPostalCodeAreExtracted() {
        #expect(AddressMatching.unitSuffix(in: "8421, rue Pie-IX, app. 3") == "app. 3")
        #expect(AddressMatching.unitSuffix(in: "8421 rue Pie-IX") == nil)
        #expect(AddressMatching.postalCode(in: "8421 Boulevard Pie-IX, Montréal QC H1Z 3T8") == "H1Z 3T8")
        #expect(AddressMatching.postalCode(in: "h2r1a1") == "H2R 1A1")
        #expect(AddressMatching.withoutCountry("8150 Boulevard Pie-IX, Montréal QC, Canada") == "8150 Boulevard Pie-IX, Montréal QC")
    }

    // MARK: Champ

    @Test func validAddressIsNormalizedAndKeepsItsPosition() async throws {
        let model = AddressFieldModel(validator: FakeAddressValidator())
        #expect(model.status(for: "") == .empty)
        #expect(model.status(for: "8150 boul. Pie-IX") == .edited)
        #expect(!model.isAccepted("8150 boul. Pie-IX"))

        let normalized = try #require(await model.validate("8150 boul. Pie-IX"))
        #expect(normalized == "8150 Boulevard Pie-IX, Montréal QC H1Z 3T6")
        #expect(model.status(for: normalized) == .valid)
        #expect(model.isAccepted(normalized))
        let address = try #require(model.validatedAddress(for: normalized))
        #expect(address.geohash().count == 7)
        #expect(address.geohash().hasPrefix("f25"), "Montréal")
    }

    /// Q-039 : une erreur réseau n'est pas « introuvable » : l'adresse tapée est gardée, sans bloquer.
    @Test func offlineValidationKeepsTypedAddressWithoutBlocking() async {
        let model = AddressFieldModel(validator: FakeAddressValidator(isOffline: true))
        #expect(await model.validate("8150 boul. Pie-IX") == "8150 boul. Pie-IX")
        #expect(model.status(for: "8150 boul. Pie-IX") == .unverified)
        #expect(!model.blocksSaving("8150 boul. Pie-IX"))
        #expect(model.isAccepted("8150 boul. Pie-IX"))
        #expect(model.validatedAddress(for: "8150 boul. Pie-IX") == nil, "pas de position inventée")
        #expect(await model.ensureValid("8150 boul. Pie-IX") == "8150 boul. Pie-IX")
    }

    @Test func offlineEnsureValidAcceptsUncheckedAddress() async {
        let model = AddressFieldModel(validator: FakeAddressValidator(isOffline: true))
        #expect(await model.ensureValid("1234 rue Jarry") == "1234 rue Jarry")
        #expect(model.status(for: "1234 rue Jarry") == .unverified)
    }

    @Test func unknownAddressIsNotFoundAndBlocksSaving() async {
        let model = AddressFieldModel(validator: FakeAddressValidator())
        #expect(await model.validate("99999 rue Inexistante") == nil)
        #expect(model.status(for: "99999 rue Inexistante") == .notFound)
        #expect(model.blocksSaving("99999 rue Inexistante"))
        #expect(!model.isAccepted("99999 rue Inexistante"))
        #expect(await model.ensureValid("99999 rue Inexistante") == nil)
        // Une fois corrigée, l'adresse n'est plus bloquée.
        #expect(model.status(for: "8150 boul. Pie-IX") == .edited)
        #expect(!model.blocksSaving("8150 boul. Pie-IX"))
    }

    @Test func savedAddressIsAcceptedUntilEdited() async {
        let model = AddressFieldModel(validator: FakeAddressValidator())
        model.accept(saved: "Rue Jarry Est, Saint-Michel, Montréal")
        #expect(model.status(for: "Rue Jarry Est, Saint-Michel, Montréal") == .saved)
        #expect(model.isAccepted("Rue Jarry Est, Saint-Michel, Montréal"))
        #expect(await model.ensureValid("Rue Jarry Est, Saint-Michel, Montréal") == "Rue Jarry Est, Saint-Michel, Montréal")
        #expect(model.validatedAddress(for: "Rue Jarry Est, Saint-Michel, Montréal") == nil, "pas de nouvelle position")
        #expect(model.status(for: "Rue Jarry, Montréal") == .edited)
        #expect(!model.isAccepted("Rue Jarry, Montréal"))
    }

    @Test func pickingSuggestionValidatesIt() async throws {
        let model = AddressFieldModel(validator: FakeAddressValidator())
        await model.refreshSuggestions(for: "7420 Ogil")
        let suggestion = try #require(model.suggestions.first)
        #expect(suggestion.title == "7420 Avenue Ogilvy")
        let normalized = try #require(await model.pick(suggestion))
        #expect(normalized == "7420 Avenue Ogilvy, Montréal QC H3N 1N4")
        #expect(model.status(for: normalized) == .valid)
        #expect(model.suggestions.isEmpty)
    }

    @Test func noSuggestionsOnceValidOrTooShort() async throws {
        let model = AddressFieldModel(validator: FakeAddressValidator())
        await model.refreshSuggestions(for: "74")
        #expect(model.suggestions.isEmpty)
        let normalized = try #require(await model.validate("7420 Ogilvy"))
        await model.refreshSuggestions(for: normalized)
        #expect(model.suggestions.isEmpty)
    }

    @Test func apartmentIsKeptAfterNormalization() async throws {
        let model = AddressFieldModel(validator: FakeAddressValidator())
        let normalized = try #require(await model.validate("8150 boul. Pie-IX, app. 3"))
        #expect(normalized == "8150 Boulevard Pie-IX, Montréal QC H1Z 3T6, app. 3")
    }

    @Test func streetLineStyleWritesNumberAndStreetOnly() async throws {
        let model = AddressFieldModel(validator: FakeAddressValidator(), style: .streetLine)
        let normalized = try #require(await model.validate("1234 rue jarry est"))
        #expect(normalized == "1234 Rue Jarry E")
        #expect(model.validatedAddress(for: normalized)?.postalCode == "H2R 1A1")
    }

    @Test func emptyOptionalAddressIsAccepted() async {
        let model = AddressFieldModel(validator: FakeAddressValidator())
        #expect(model.isAccepted("  ", optional: true))
        #expect(!model.isAccepted("  "))
    }

    // MARK: Onboarding (T-159)

    @Test func streetLineSplitsIntoNumberAndStreet() {
        #expect(PostSignupOnboardingViewModel.split(streetLine: "1234, rue Jarry Est") == ("1234", "rue Jarry Est"))
        #expect(PostSignupOnboardingViewModel.split(streetLine: "1234 Rue Jarry E") == ("1234", "Rue Jarry E"))
        #expect(PostSignupOnboardingViewModel.split(streetLine: "rue Jarry") == ("", "rue Jarry"))
    }

    @Test func appleDirectionAbbreviationMatchesTypedStreet() {
        let typed = HouseholdAddress(streetNumber: "1234", street: "rue Jarry Est", postalCode: "H2R 1A1")
        let apple = HouseholdAddress(streetNumber: "1234", street: "Rue Jarry E", postalCode: "H2R 1A1")
        #expect(typed.key == apple.key)
    }
}
