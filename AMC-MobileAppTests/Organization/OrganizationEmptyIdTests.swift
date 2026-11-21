import Testing
@testable import AMC_MobileApp

/// Compte sans organisme rattaché : l'id reste vide, et le contexte doit le dire pour que la page Organisme
/// n'appelle jamais Firestore avec `organizations/""` (crash « Document path cannot be empty »).
@MainActor
struct OrganizationEmptyIdTests {
    @Test func contextWithoutOrganizationReportsNoOrganization() {
        let context = AppContext(
            repositories: .fake().cached(), userId: "", householdId: "", groupId: nil,
            vendorId: "", status: .unresolved
        )
        #expect(context.organizationId.isEmpty)
        #expect(!context.hasOrganization)
    }
}
