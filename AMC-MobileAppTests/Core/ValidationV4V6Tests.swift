import Foundation
import Testing
@testable import AMC_MobileApp

/// Audit de validation V4 à V6 : code postal A1A 1A1, quartier ≤ 80, taille du foyer alignée sur le serveur.
struct ValidationV4V6Tests {
    @Test("V4 : seul un code postal canadien A1A 1A1 est accepté")
    func postalCodeFormat() {
        #expect(PostalCode.normalized("H2R 1A1") == "h2r1a1")
        #expect(PostalCode.normalized(" h2r-1a1 ") == "h2r1a1")
        #expect(PostalCode.normalized("123456") == nil)
        #expect(PostalCode.normalized("ABCDEF") == nil)
        #expect(PostalCode.normalized("H2R 1A") == nil)
        #expect(PostalCode.normalized("H2R 1A1 2") == nil)
    }

    @Test("V4 : une adresse au code postal mal formé n'a pas de clé")
    func addressKeyNeedsValidPostalCode() {
        let bad = HouseholdAddress(streetNumber: "1234", street: "Jarry Est", postalCode: "123456")
        #expect(bad.key == nil)
        #expect(!bad.isComplete)
        let good = HouseholdAddress(streetNumber: "1234", street: "Jarry Est", postalCode: "h2r 1a1")
        #expect(good.key == "1234jarryest-h2r1a1")
    }

    @Test("V5 : le quartier d'un groupe fait 80 caractères au plus")
    func neighborhoodMaxLength() throws {
        let ok = GroupRules.Draft(name: "Voisins", neighborhood: String(repeating: "a", count: 80), centerGeohash: "f25eh8")
        #expect(try GroupRules.validate(ok).neighborhood.count == 80)
        let tooLong = GroupRules.Draft(name: "Voisins", neighborhood: String(repeating: "a", count: 81), centerGeohash: "f25eh8")
        #expect(throws: AppError.self) { try GroupRules.validate(tooLong) }
    }

    @Test("V6 : la taille du foyer suit la limite du serveur (1 à 30)") @MainActor
    func householdSizeRange() {
        #expect(HouseholdMembership.sizeRange == 1...30)
        #expect(HouseholdProfileViewModel.sizeRange == HouseholdMembership.sizeRange)
        #expect(PostSignupOnboardingViewModel.sizeRange == HouseholdMembership.sizeRange)
    }
}
