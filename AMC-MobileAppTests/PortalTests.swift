import Testing
@testable import AMC_MobileApp

@MainActor
struct PortalTests {
    @Test func allPortalsHaveTitleAndSymbol() {
        for portal in Portal.allCases {
            #expect(!portal.title.isEmpty)
            #expect(!portal.systemImage.isEmpty)
        }
    }

    @Test func rawValueRoundTripsForAppStorage() {
        for portal in Portal.allCases {
            #expect(Portal(rawValue: portal.rawValue) == portal)
        }
    }
}
