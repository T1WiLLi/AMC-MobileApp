// InviteLinkRouterTests.swift
// B-058 : les liens d'invitation ouvrent l'app. Parsing des liens reçus, code en attente
// pris une seule fois, autres liens laissés à Google Sign-In, QR de l'invitation.

import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
struct InviteLinkRouterTests {
    @Test(arguments: [
        ("grenier://join/VIL4K7", "VIL4K7"),
        ("grenier://join/vil4k7", "VIL4K7"),
        ("GRENIER://JOIN/VIL4K7", "VIL4K7"),
        ("grenier://join/VIL4K7/", "VIL4K7"),
        ("https://grenier.app/join/VIL4K7", "VIL4K7"),
        // Ancien QR de la carte d'invitation, encore accepté.
        ("grenier://rejoindre?code=PARCEX", "PARCEX"),
        ("grenier://rejoindre?code=parcex&ref=qr", "PARCEX"),
    ])
    func linkOpensJoinWithItsCode(link: String, code: String) throws {
        let router = InviteLinkRouter()
        #expect(router.handle(try #require(URL(string: link))))
        #expect(router.pendingCode == code)
    }

    @Test(arguments: [
        "com.googleusercontent.apps.123:/oauth2redirect?code=abc",
        "grenier://part/GRN-4821",
        "grenier://join",
        "grenier://join/VIL4K7/extra",
        "grenier://rejoindre",
        "grenier://rejoindre/PARCEX?code=PARCEX",
        "grenier://rejoindre?code=AB",
        "https://evil.app/join/VIL4K7",
    ])
    func otherLinksAreLeftAlone(link: String) throws {
        let router = InviteLinkRouter()
        #expect(!router.handle(try #require(URL(string: link))))
        #expect(router.pendingCode == nil)
    }

    @Test func pendingCodeIsTakenOnce() throws {
        let router = InviteLinkRouter()
        router.handle(try #require(URL(string: "grenier://join/VIL4K7")))
        #expect(router.consume() == "VIL4K7")
        #expect(router.pendingCode == nil)
        #expect(router.consume() == nil)
    }

    @Test func aNewerLinkReplacesThePendingOne() throws {
        let router = InviteLinkRouter()
        router.handle(try #require(URL(string: "grenier://join/VIL4K7")))
        router.handle(try #require(URL(string: "grenier://join/ABC234")))
        #expect(router.consume() == "ABC234")
    }

    @Test func anIgnoredLinkKeepsThePendingCode() throws {
        let router = InviteLinkRouter()
        router.handle(try #require(URL(string: "grenier://join/VIL4K7")))
        router.handle(try #require(URL(string: "https://evil.app/join/ABC234")))
        #expect(router.pendingCode == "VIL4K7")
    }

    @Test func invitationQREncodesTheAppLink() throws {
        let invitation = GroupInvitation(code: "VIL4K7", groupId: "g1", createdBy: "creator", createdAt: .now)
        let payload = InvitationQRSheet.payload(for: invitation)
        #expect(payload == "grenier://join/VIL4K7")
        #expect(GroupRules.inviteCode(from: try #require(URL(string: payload))) == "VIL4K7")
        #expect(QRMatrix(payload) != nil)
    }

    @Test func demoInvitationsOpenTheirGroup() throws {
        for invitation in FakeData.montreal.invitations {
            let url = try #require(invitation.appURL)
            #expect(GroupRules.inviteCode(from: url) == invitation.code)
        }
    }
}
