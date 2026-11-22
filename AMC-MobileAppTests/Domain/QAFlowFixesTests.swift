// QAFlowFixesTests.swift
// Vérification des flows : message d'invitation collé en entier, notification touchée → bon écran.

import Foundation
import Testing
@testable import AMC_MobileApp

struct QAFlowFixesTests {
    // MARK: Message d'invitation collé

    @Test func aPastedFrenchShareMessageGivesItsCode() {
        let message = "Je t'invite dans « Cuisine » sur LeGrenier, un groupe privé. Cette invitation sert une seule fois : https://grenier.app/join/VIL4K7 (code VIL4K7)"
        #expect(GroupRules.inviteCode(fromUserInput: message) == "VIL4K7")
        #expect(GroupRules.inviteCode(inMessage: message) == "VIL4K7")
    }

    @Test func aPastedEnglishShareMessageGivesItsCode() {
        let message = "Join “Kitchen” on LeGrenier, a private group. This invitation works once: https://grenier.app/join/VIL4K7 (code VIL4K7)"
        #expect(GroupRules.inviteCode(fromUserInput: message) == "VIL4K7")
    }

    @Test func aMessageWithOnlyTheCodeGivesIt() {
        #expect(GroupRules.inviteCode(inMessage: "Rejoins notre groupe avec le code vil4k7 !") == "VIL4K7")
    }

    @Test func aSentenceWithoutCodeGivesNothing() {
        #expect(GroupRules.inviteCode(fromUserInput: "Rejoins mon groupe stp") == nil)
    }

    @Test @MainActor func theJoinSheetKeepsTheCodeOfAPastedMessage() {
        let message = "Je t'invite dans « Cuisine » sur LeGrenier : https://grenier.app/join/VIL4K7 (code VIL4K7)"
        #expect(JoinWithCodeViewModel.formattedInput(message) == "VIL4K7")
        // Une phrase sans code n'est pas coupée en faux code (« REJOIN »).
        #expect(JoinWithCodeViewModel.formattedInput("Rejoins mon groupe") == "Rejoins mon groupe")
        // Un code trop long tapé d'un bloc reste coupé.
        #expect(JoinWithCodeViewModel.formattedInput("vil4k7xyz") == "VIL4K7")
    }

    // MARK: Notification touchée

    private typealias Key = GrenierNotification.UserInfoKey

    @Test @MainActor func deliveryAndPickupReminderOpenPickup() {
        for kind in [GrenierNotification.Kind.delivery, .pickupReminder] {
            let userInfo: [AnyHashable: Any] = [Key.kind: kind.rawValue, Key.groupId: "g1"]
            #expect(NotificationRouter.destination(userInfo: userInfo) == .pickup)
        }
    }

    @Test @MainActor func groupEventsOpenTheGroup() {
        for kind in [GrenierNotification.Kind.tier, .outcome, .deadlineReminder] {
            let userInfo: [AnyHashable: Any] = [Key.kind: kind.rawValue, Key.groupId: "g1"]
            #expect(NotificationRouter.destination(userInfo: userInfo) == .group(id: "g1"))
        }
    }

    @Test @MainActor func aForeignNotificationOpensNothing() {
        #expect(NotificationRouter.destination(userInfo: [:]) == nil)
        #expect(NotificationRouter.destination(userInfo: [Key.kind: "autre"]) == nil)
        #expect(NotificationRouter.destination(userInfo: [Key.kind: "tier", Key.groupId: ""]) == nil)
    }

    @Test @MainActor func aDestinationIsConsumedOnce() {
        let router = NotificationRouter()
        router.open(nil)
        #expect(router.pendingDestination == nil)

        router.open(.group(id: "g1"))
        router.consumePickup()
        #expect(router.pendingDestination == .group(id: "g1"))
        #expect(router.consumeGroup() == "g1")
        #expect(router.consumeGroup() == nil)

        router.open(.pickup)
        #expect(router.consumeGroup() == nil)
        router.consumePickup()
        #expect(router.pendingDestination == nil)
    }
}
