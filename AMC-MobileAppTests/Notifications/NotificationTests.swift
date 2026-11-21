import Foundation
import Testing
import UserNotifications
@testable import AMC_MobileApp

@MainActor
struct NotificationContentTests {
    private static let montreal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Montreal")!
        return calendar
    }()

    private static func date(_ hour: Int, _ minute: Int = 0, day: Int = 28) -> Date {
        montreal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private static let order = GrenierNotification.Order(
        orderId: "go-riz", groupId: "parc-ex-ouest", groupName: "Parc-Ex Ouest", productName: "le riz"
    )

    private static func make(_ event: GrenierNotification.Event) -> GrenierNotification {
        GrenierNotification(order: order, event: event)
    }

    private static let slot = PickupSlot(start: date(17), end: date(19, 30))

    @Test func tierUnlockedReadsLikeTheMockup() {
        let notification = Self.make(.tierUnlocked(priceCents: 260, unit: "kg"))
        let content = notification.makeContent(calendar: Self.montreal)
        #expect(content.title == "Palier débloqué à Parc-Ex Ouest !")
        #expect(content.body == "Le riz passe à \(Money.format(260))/kg.")
        #expect(content.threadIdentifier == "grenier.group.parc-ex-ouest")
        #expect(content.interruptionLevel == .active)
        #expect(content.userInfo["orderId"] as? String == "go-riz")
        #expect(content.userInfo["kind"] as? String == "tier")
    }

    @Test func closedShowsFinalPrice() {
        let content = Self.make(.orderClosed(finalPriceCents: 210, unit: "kg")).makeContent()
        #expect(content.title == "Commande fermée à Parc-Ex Ouest")
        #expect(content.body.hasPrefix("Prix final : \(Money.format(210))/kg."))
    }

    @Test func cancelledExplainsTheMinimum() {
        let content = Self.make(.orderCancelled).makeContent()
        #expect(content.title == "Commande annulée à Parc-Ex Ouest")
        #expect(content.body == "Le minimum n'a pas été atteint pour le riz. Tu ne paies rien.")
    }

    @Test func deliveryNamesThePickupPoint() {
        let content = Self.make(.deliveryArrived(pickupPointName: "Centre William-Hingston")).makeContent()
        #expect(content.title == "C'est arrivé à Centre William-Hingston !")
        #expect(content.body.hasPrefix("Le riz t'attend."))
    }

    @Test func pickupReminderIsTimeSensitiveWithSlotHours() {
        let notification = Self.make(.pickupReminder(pickupPointName: "Centre William-Hingston", slot: Self.slot))
        let content = notification.makeContent(calendar: Self.montreal)
        #expect(content.title == "Cueillette dans 1 h")
        #expect(content.body == "Le riz t'attend à Centre William-Hingston, de 17 h à 19 h 30.")
        #expect(content.interruptionLevel == .timeSensitive)
        #expect(content.threadIdentifier == "grenier.group.parc-ex-ouest")
    }

    @Test func pickupReminderTriggersOneHourBeforeTheSlot() throws {
        let notification = Self.make(.pickupReminder(pickupPointName: "Centre", slot: Self.slot))
        let trigger = try #require(notification.makeTrigger(calendar: Self.montreal, now: Self.date(9)) as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.hour == 16)
        #expect(trigger.dateComponents.minute == 0)
        #expect(trigger.dateComponents.day == 28)
        #expect(!trigger.repeats)
    }

    @Test func pickupReminderExpiresInsideTheLastHour() {
        let notification = Self.make(.pickupReminder(pickupPointName: "Centre", slot: Self.slot))
        #expect(!notification.isExpired(now: Self.date(15, 59)))
        #expect(notification.isExpired(now: Self.date(16, 30)))
        #expect(notification.makeTrigger(calendar: Self.montreal, now: Self.date(16, 30)) == nil)
    }

    @Test func immediateEventsHaveNoTrigger() {
        #expect(Self.make(.orderCancelled).makeTrigger() == nil)
        #expect(Self.make(.tierUnlocked(priceCents: 260, unit: "kg")).makeTrigger() == nil)
    }

    @Test func identifiersAreStablePerOrder() {
        let first = Self.make(.tierUnlocked(priceCents: 300, unit: "kg"))
        let second = Self.make(.tierUnlocked(priceCents: 260, unit: "kg"))
        #expect(first.identifier == "grenier.order.go-riz.tier")
        #expect(first.identifier == second.identifier)
        // Fermeture et annulation se remplacent l'une l'autre.
        #expect(Self.make(.orderClosed(finalPriceCents: 210, unit: "kg")).identifier == Self.make(.orderCancelled).identifier)
        #expect(Set(GrenierNotification.Kind.allCases.map { $0.identifier(forOrder: "go-riz") }).count == 5)
    }
}

@MainActor
struct NotificationSchedulerTests {
    private static let order = GrenierNotification.Order(
        orderId: "go-riz", groupId: "parc-ex-ouest", groupName: "Parc-Ex Ouest", productName: "le riz"
    )

    @Test func authorizationIsNeverRequestedWithoutAnExplicitCall() async {
        let scheduler = FakeNotificationScheduler()
        #expect(await scheduler.authorizationStatus() == .notDetermined)
        #expect(scheduler.requestCount == 0)
    }

    @Test func grantedRequestAuthorizes() async throws {
        let scheduler = FakeNotificationScheduler()
        #expect(try await scheduler.requestAuthorization() == .authorized)
        #expect(scheduler.requestCount == 1)
    }

    @Test func refusalThrowsPermissionDenied() async {
        let scheduler = FakeNotificationScheduler(grantsOnRequest: false)
        await #expect(throws: AppError.permissionDenied) { try await scheduler.requestAuthorization() }
        #expect(await scheduler.authorizationStatus() == .denied)
        // Déjà refusé : iOS ne redemande pas, seul Réglages peut rallumer.
        await #expect(throws: AppError.notificationsDenied) { try await scheduler.requestAuthorization() }
        #expect(scheduler.requestCount == 1)
    }

    @Test func schedulingWhenDisabledThrows() async {
        let scheduler = FakeNotificationScheduler(status: .denied)
        await #expect(throws: AppError.notificationsDenied) {
            try await scheduler.schedule(GrenierNotification(order: Self.order, event: .orderCancelled))
        }
    }

    @Test func schedulingReplacesBySameIdentifierAndCancels() async throws {
        let scheduler = FakeNotificationScheduler(status: .authorized)
        try await scheduler.schedule(GrenierNotification(order: Self.order, event: .tierUnlocked(priceCents: 300, unit: "kg")))
        try await scheduler.schedule(GrenierNotification(order: Self.order, event: .tierUnlocked(priceCents: 260, unit: "kg")))
        try await scheduler.schedule(GrenierNotification(order: Self.order, event: .deliveryArrived(pickupPointName: "Centre")))
        #expect(scheduler.scheduled.count == 2)
        #expect(scheduler.scheduled["grenier.order.go-riz.tier"]?.event == .tierUnlocked(priceCents: 260, unit: "kg"))

        await scheduler.cancel(.tier, forOrder: "go-riz")
        #expect(scheduler.scheduled.count == 1)
        await scheduler.cancelAll(forOrder: "go-riz")
        #expect(scheduler.scheduled.isEmpty)
    }

    @Test func expiredPickupReminderIsSkipped() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let slot = PickupSlot(start: start, end: start.addingTimeInterval(7200))
        let scheduler = FakeNotificationScheduler(status: .authorized, now: start.addingTimeInterval(-1800))
        let scheduled = try await scheduler.schedule(GrenierNotification(order: Self.order, event: .pickupReminder(pickupPointName: "Centre", slot: slot)))
        #expect(!scheduled)
        #expect(scheduler.scheduled.isEmpty)
    }

    @Test func systemStatusMapping() {
        #expect(NotificationAuthorizationStatus(.provisional) == .authorized)
        #expect(NotificationAuthorizationStatus(.ephemeral) == .authorized)
        #expect(NotificationAuthorizationStatus(.denied) == .denied)
        #expect(NotificationAuthorizationStatus(.notDetermined) == .notDetermined)
    }
}
