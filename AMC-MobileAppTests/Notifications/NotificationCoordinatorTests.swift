import Foundation
import Testing
@testable import AMC_MobileApp

/// Enveloppe du faux planificateur qui compte chaque appel (le faux ne garde qu'une notification par identifiant).
@MainActor
private final class RecordingNotificationScheduler: NotificationScheduler {
    let fake: FakeNotificationScheduler
    private(set) var scheduleCalls: [GrenierNotification] = []
    private(set) var cancelAllCalls: [String] = []
    private(set) var cancelCalls: [(GrenierNotification.Kind, String)] = []

    init(now: Date = .now) {
        fake = FakeNotificationScheduler(status: .authorized, now: now)
    }

    var scheduled: [String: GrenierNotification] { fake.scheduled }

    func calls(_ kind: GrenierNotification.Kind) -> [GrenierNotification] {
        scheduleCalls.filter { $0.kind == kind }
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus { await fake.authorizationStatus() }

    @discardableResult
    func requestAuthorization() async throws -> NotificationAuthorizationStatus { try await fake.requestAuthorization() }

    @discardableResult
    func schedule(_ notification: GrenierNotification) async throws -> Bool {
        scheduleCalls.append(notification)
        return try await fake.schedule(notification)
    }

    func cancel(_ kind: GrenierNotification.Kind, forOrder orderId: String) async {
        cancelCalls.append((kind, orderId))
        await fake.cancel(kind, forOrder: orderId)
    }

    func cancelAll(forOrder orderId: String) async {
        cancelAllCalls.append(orderId)
        await fake.cancelAll(forOrder: orderId)
    }
}

/// Attend qu'une condition devienne vraie (temps réel simulé), au plus ~2 s.
@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
struct NotificationCoordinatorTests {
    private static let data = FakeData.montreal
    private static let offer = data.offers.first { $0.id == FakeData.ID.potatoOffer }!
    private static let pickupPoint = data.pickupPoints.first { $0.id == FakeData.ID.jarryPickup }!
    private static let order = data.groupOrders.first { $0.id == FakeData.ID.potatoOrder }!

    private static let context = GroupOrderNotificationContext(
        groupName: "Voisins de Saint-Michel",
        productName: "les pommes de terre jaunes",
        unit: "sac de 10 kg",
        offer: offer,
        pickupPoint: pickupPoint
    )

    private static func order(
        status: GroupOrder.Status = .reached, tier: Int? = 0, shares: Int = 19, slots: [PickupSlot]? = nil
    ) -> GroupOrder {
        var copy = order
        copy.status = status
        copy.currentTierIndex = tier
        copy.committedShares = shares
        if let slots { copy.pickupSlots = slots }
        return copy
    }

    private func makeCoordinator() -> (NotificationCoordinator, RecordingNotificationScheduler) {
        let scheduler = RecordingNotificationScheduler()
        let coordinator = NotificationCoordinator(scheduler: scheduler, store: InMemoryLastKnownStateStore())
        return (coordinator, scheduler)
    }

    // MARK: Diff pur

    @Test func tierGoingUpProducesTierUnlockedWithTheNewPrice() {
        let events = NotificationCoordinator.events(
            from: Self.order(tier: 0), to: Self.order(tier: 1, shares: 20), context: Self.context
        )
        #expect(events == [.tierUnlocked(priceCents: 990, unit: "sac de 10 kg")])
    }

    @Test func firstSightIsABaselineWithoutImmediateNotification() {
        let events = NotificationCoordinator.events(from: nil, to: Self.order(tier: 1), context: Self.context)
        #expect(events.isEmpty)
    }

    @Test func closingFreezesTheFinalPrice() {
        let events = NotificationCoordinator.events(
            from: Self.order(tier: 1, shares: 20), to: Self.order(status: .closed, tier: 1, shares: 20), context: Self.context
        )
        #expect(events == [.orderClosed(finalPriceCents: 990, unit: "sac de 10 kg")])
    }

    @Test func deliveryNamesThePickupPoint() {
        let events = NotificationCoordinator.events(
            from: Self.order(status: .closed), to: Self.order(status: .delivered), context: Self.context
        )
        #expect(events == [.deliveryArrived(pickupPointName: "Chez Amina, rue Jarry")])
    }

    @Test func tierWithoutOfferIsSkipped() {
        var context = Self.context
        context.offer = nil
        let events = NotificationCoordinator.events(from: Self.order(tier: 0), to: Self.order(tier: 1), context: context)
        #expect(events.isEmpty)
    }

    // MARK: Coordinateur

    @Test func tierCrossedSchedulesExactlyOneNotification() async {
        let (coordinator, scheduler) = makeCoordinator()
        await coordinator.handle(Self.order(tier: 0), context: Self.context)
        await coordinator.handle(Self.order(tier: 1, shares: 20), context: Self.context)

        let tiers = scheduler.calls(.tier)
        #expect(tiers.count == 1)
        #expect(tiers.first?.event == .tierUnlocked(priceCents: 990, unit: "sac de 10 kg"))
        #expect(tiers.first?.order == .init(
            orderId: FakeData.ID.potatoOrder, groupId: FakeData.ID.saintMichel,
            groupName: "Voisins de Saint-Michel", productName: "les pommes de terre jaunes"
        ))
    }

    @Test func sameStateTwiceSchedulesNothingMore() async {
        let (coordinator, scheduler) = makeCoordinator()
        await coordinator.handle(Self.order(tier: 0), context: Self.context)
        await coordinator.handle(Self.order(tier: 1, shares: 20), context: Self.context)
        let callsAfterFirst = scheduler.scheduleCalls.count

        await coordinator.handle(Self.order(tier: 1, shares: 20), context: Self.context)
        await coordinator.handle(Self.order(tier: 1, shares: 20), context: Self.context)

        #expect(scheduler.scheduleCalls.count == callsAfterFirst)
    }

    @Test func cancellationClearsTheOrderThenAnnouncesIt() async {
        let (coordinator, scheduler) = makeCoordinator()
        await coordinator.handle(Self.order(tier: 0), context: Self.context)
        #expect(scheduler.scheduled[GrenierNotification.Kind.pickupReminder.identifier(forOrder: FakeData.ID.potatoOrder)] != nil)

        await coordinator.handle(Self.order(status: .cancelled, tier: 0), context: Self.context)

        #expect(scheduler.cancelAllCalls == [FakeData.ID.potatoOrder])
        let id = FakeData.ID.potatoOrder
        #expect(scheduler.scheduled[GrenierNotification.Kind.pickupReminder.identifier(forOrder: id)] == nil)
        #expect(scheduler.scheduled[GrenierNotification.Kind.outcome.identifier(forOrder: id)]?.event == .orderCancelled)
    }

    @Test func pickupReminderIsScheduledForTheNextSlot() async throws {
        let (coordinator, scheduler) = makeCoordinator()
        let start = Date.now.addingTimeInterval(2 * 86_400)
        let slot = PickupSlot(start: start, end: start.addingTimeInterval(3_600))

        await coordinator.handle(Self.order(slots: [slot]), context: Self.context)

        let reminder = try #require(
            scheduler.scheduled[GrenierNotification.Kind.pickupReminder.identifier(forOrder: FakeData.ID.potatoOrder)]
        )
        #expect(reminder.event == .pickupReminder(pickupPointName: "Chez Amina, rue Jarry", slot: slot))
        #expect(reminder.fireDate() == start.addingTimeInterval(-GrenierNotification.pickupReminderLead))

        // Même créneau, même état : pas de reprogrammation.
        await coordinator.handle(Self.order(slots: [slot]), context: Self.context)
        #expect(scheduler.calls(.pickupReminder).count == 1)
    }

    @Test func pastSlotsAreSkippedAndOpenOrdersGetNoReminder() async {
        let (coordinator, scheduler) = makeCoordinator()
        let past = PickupSlot(start: .now.addingTimeInterval(-3_600), end: .now)
        await coordinator.handle(Self.order(slots: [past]), context: Self.context)
        await coordinator.handle(Self.order(status: .open, tier: nil, shares: 5).withId("autre"), context: Self.context)
        #expect(scheduler.calls(.pickupReminder).isEmpty)
    }

    @Test func persistedStateSurvivesANewCoordinator() async {
        let store = InMemoryLastKnownStateStore()
        let scheduler = RecordingNotificationScheduler()
        await NotificationCoordinator(scheduler: scheduler, store: store).handle(Self.order(tier: 0), context: Self.context)
        // Relance de l'app (arrière-plan) : nouvel objet, même mémoire.
        await NotificationCoordinator(scheduler: scheduler, store: store)
            .handle(Self.order(tier: 1, shares: 20), context: Self.context)
        #expect(scheduler.calls(.tier).count == 1)
    }

    @Test func userDefaultsStoreRoundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "grenier.tests.\(UUID().uuidString)"))
        let store = UserDefaultsLastKnownStateStore(defaults: defaults)
        store.save(Self.order(tier: 1))
        store.saveOffers([Self.offer])
        let reloaded = UserDefaultsLastKnownStateStore(defaults: defaults)
        #expect(reloaded.groupOrder(id: FakeData.ID.potatoOrder) == Self.order(tier: 1))
        #expect(reloaded.offer(id: FakeData.ID.potatoOffer) == Self.offer)
    }

    // MARK: Date limite du lot

    @Test func deadlineReminderReadsWellAndFires24HoursBefore() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Montreal")!
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 17))!
        let notification = GrenierNotification(
            order: .init(orderId: "go-riz", groupId: "parc-ex-ouest", groupName: "Parc-Ex Ouest", productName: "le riz"),
            event: .deadlineReminder(deadline: deadline)
        )
        let content = notification.makeContent(calendar: calendar)
        #expect(content.title == "Plus que 24 h à Parc-Ex Ouest")
        #expect(content.body == "Le riz : la commande ferme demain à 17 h. Invite tes voisins pour faire baisser le prix.")
        #expect(notification.kind == .deadlineReminder)
        #expect(notification.identifier == "grenier.order.go-riz.deadlineReminder")

        let now = deadline.addingTimeInterval(-3 * 86_400)
        #expect(notification.fireDate(now: now) == deadline.addingTimeInterval(-86_400))
        #expect(notification.makeTrigger(calendar: calendar, now: now) != nil)
        #expect(notification.isExpired(now: deadline.addingTimeInterval(-3_600)))
    }

    @Test func openOrderGetsADeadlineReminderOnce() async throws {
        let (coordinator, scheduler) = makeCoordinator()
        var context = Self.context
        context.offer?.deadline = .now.addingTimeInterval(3 * 86_400)
        let deadline = try #require(context.offer?.deadline)

        await coordinator.handle(Self.order(status: .open), context: context)
        await coordinator.handle(Self.order(status: .open, shares: 20), context: context)

        let reminders = scheduler.calls(.deadlineReminder)
        #expect(reminders.map(\.event) == [.deadlineReminder(deadline: deadline)])
        #expect(scheduler.scheduled[GrenierNotification.Kind.deadlineReminder.identifier(forOrder: FakeData.ID.potatoOrder)] != nil)
    }

    @Test func deadlineInsideTheLast24HoursIsSkipped() async {
        let (coordinator, scheduler) = makeCoordinator()
        var context = Self.context
        context.offer?.deadline = .now.addingTimeInterval(3_600)
        await coordinator.handle(Self.order(status: .open), context: context)
        #expect(scheduler.calls(.deadlineReminder).isEmpty)
    }

    @Test func closingCancelsTheDeadlineReminder() async {
        let (coordinator, scheduler) = makeCoordinator()
        var context = Self.context
        context.offer?.deadline = .now.addingTimeInterval(3 * 86_400)
        await coordinator.handle(Self.order(status: .reached, tier: 1, shares: 20), context: context)
        let id = GrenierNotification.Kind.deadlineReminder.identifier(forOrder: FakeData.ID.potatoOrder)
        #expect(scheduler.scheduled[id] != nil)

        await coordinator.handle(Self.order(status: .closed, tier: 1, shares: 20), context: context)

        #expect(scheduler.scheduled[id] == nil)
        #expect(scheduler.cancelCalls.contains { $0.0 == .deadlineReminder && $0.1 == FakeData.ID.potatoOrder })
    }

    // MARK: Temps réel

    @Test func observeFollowsTheOrderAndStopsWhenCancelled() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let (coordinator, scheduler) = makeCoordinator()
        let task = Task {
            await coordinator.observe(groupOrderIds: [FakeData.ID.potatoOrder], repositories: repositories)
        }

        // Premier état (19 parts) : base, plus le rappel de cueillette.
        await waitUntil { !scheduler.calls(.pickupReminder).isEmpty }
        #expect(scheduler.calls(.tier).isEmpty)

        // La part d'Amina fait franchir le palier de 20.
        try await repositories.groupOrders.setShare(
            quantity: 1, householdId: FakeData.ID.aminaHousehold, groupOrderId: FakeData.ID.potatoOrder
        )
        await waitUntil { !scheduler.calls(.tier).isEmpty }
        #expect(scheduler.calls(.tier).map(\.event) == [.tierUnlocked(priceCents: 990, unit: "sac de 10 kg")])
        #expect(scheduler.calls(.tier).first?.order.groupName == "Voisins de Saint-Michel")

        task.cancel()
        await task.value

        // Après l'arrêt : un nouveau palier (30 parts) ne notifie plus.
        try await repositories.groupOrders.setShare(
            quantity: 11, householdId: FakeData.ID.aminaHousehold, groupOrderId: FakeData.ID.potatoOrder
        )
        try await Task.sleep(for: .milliseconds(100))
        #expect(scheduler.calls(.tier).count == 1)
    }

    @Test func contextLoadsNamesFromRepositories() async {
        let repositories = AppRepositories.fake(behavior: .instant)
        let context = await GroupOrderNotificationContext.load(for: Self.order, repositories: repositories)
        #expect(context.groupName == "Voisins de Saint-Michel")
        #expect(context.productName == "les pommes de terre jaunes")
        #expect(context.unit == "sac de 10 kg")
        #expect(context.offer?.id == FakeData.ID.potatoOffer)
        #expect(context.pickupPoint?.id == FakeData.ID.jarryPickup)
    }
}

private extension GroupOrder {
    func withId(_ id: String) -> GroupOrder {
        var copy = self
        copy.id = id
        return copy
    }
}

// MARK: - Rafraîchissement en arrière-plan

private final class FakeBackgroundTaskScheduler: BackgroundTaskScheduling {
    private(set) var registered: [String] = []
    private(set) var submitted: [(identifier: String, earliestBeginDate: Date?)] = []
    private(set) var launchHandler: (@MainActor (any BackgroundRefreshTask) -> Void)?

    func register(identifier: String, launchHandler: @escaping @MainActor (any BackgroundRefreshTask) -> Void) -> Bool {
        registered.append(identifier)
        self.launchHandler = launchHandler
        return true
    }

    func submit(identifier: String, earliestBeginDate: Date?) throws {
        submitted.append((identifier, earliestBeginDate))
    }
}

private final class FakeBackgroundRefreshTask: BackgroundRefreshTask {
    var expirationHandler: (@Sendable () -> Void)?
    private(set) var completion: Bool?

    func setTaskCompleted(success: Bool) {
        completion = success
    }
}

@MainActor
struct BackgroundRefreshTests {
    private let now = Date.now

    private func make(
        repositories: AppRepositories,
        store: InMemoryLastKnownStateStore = InMemoryLastKnownStateStore()
    ) -> (BackgroundRefresh, FakeBackgroundTaskScheduler, RecordingNotificationScheduler) {
        let tasks = FakeBackgroundTaskScheduler()
        let notifications = RecordingNotificationScheduler()
        let refresh = BackgroundRefresh(
            taskScheduler: tasks,
            coordinator: NotificationCoordinator(scheduler: notifications, store: store),
            repositories: repositories,
            store: store,
            householdId: { FakeData.ID.aminaHousehold },
            now: { [now] in now }
        )
        return (refresh, tasks, notifications)
    }

    @Test func identifierMatchesTheBundle() {
        #expect(BackgroundRefresh.identifier == "ca.amc2026.mobileapp.refresh")
    }

    @Test func registerAndScheduleUseTheIdentifier() {
        let (refresh, tasks, _) = make(repositories: .fake(behavior: .instant))
        #expect(refresh.register())
        refresh.schedule()
        #expect(tasks.registered == [BackgroundRefresh.identifier])
        #expect(tasks.submitted.map(\.identifier) == [BackgroundRefresh.identifier])
        #expect(tasks.submitted.first?.earliestBeginDate == now.addingTimeInterval(BackgroundRefresh.minimumInterval))
    }

    @Test func refreshWithoutChangeNotifiesNothing() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        try await repositories.groupOrders.setShare(
            quantity: 1, householdId: FakeData.ID.aminaHousehold, groupOrderId: FakeData.ID.potatoOrder
        )
        let (refresh, _, notifications) = make(repositories: repositories)

        #expect(await refresh.refresh())
        let afterBaseline = notifications.scheduleCalls.count
        #expect(await refresh.refresh())

        #expect(notifications.calls(.tier).isEmpty)
        #expect(notifications.scheduleCalls.count == afterBaseline)
    }

    @Test func changeBetweenTwoRefreshesNotifiesOnce() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        try await repositories.groupOrders.setShare(
            quantity: 1, householdId: FakeData.ID.aminaHousehold, groupOrderId: FakeData.ID.potatoOrder
        )
        let store = InMemoryLastKnownStateStore()
        let (refresh, _, notifications) = make(repositories: repositories, store: store)
        #expect(await refresh.refresh())
        #expect(store.offer(id: FakeData.ID.potatoOffer) != nil)
        #expect(store.share(householdId: FakeData.ID.aminaHousehold, groupOrderId: FakeData.ID.potatoOrder)?.quantity == 1)

        // Pendant que l'app dort, le groupe atteint 30 parts.
        try await repositories.groupOrders.setShare(
            quantity: 11, householdId: FakeData.ID.aminaHousehold, groupOrderId: FakeData.ID.potatoOrder
        )
        #expect(await refresh.refresh())
        #expect(await refresh.refresh())

        #expect(notifications.calls(.tier).map(\.event) == [.tierUnlocked(priceCents: 850, unit: "sac de 10 kg")])
    }

    @Test func ordersWithoutAHouseholdShareAreIgnored() async {
        let (refresh, _, notifications) = make(repositories: .fake(behavior: .instant))
        #expect(await refresh.refresh())
        #expect(notifications.scheduleCalls.isEmpty)
    }

    @Test func launchHandlerRefreshesReschedulesAndCompletes() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let (refresh, tasks, _) = make(repositories: repositories)
        refresh.register()
        let task = FakeBackgroundRefreshTask()

        let launchHandler = try #require(tasks.launchHandler)
        launchHandler(task)

        #expect(tasks.submitted.count == 1)
        #expect(task.expirationHandler != nil)
        await waitUntil { task.completion != nil }
        #expect(task.completion == true)
    }

    @Test func failingRepositoriesReportFailure() async {
        let (refresh, _, _) = make(repositories: .fake(behavior: .failing()))
        #expect(await refresh.refresh() == false)
    }
}
