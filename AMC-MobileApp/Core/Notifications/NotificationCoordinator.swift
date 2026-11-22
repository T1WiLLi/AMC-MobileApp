// NotificationCoordinator.swift
// Décide QUAND programmer les notifications locales de Grenier (T-107, S-12) : il compare l'état
// précédent d'une commande groupée au nouvel état et appelle `NotificationScheduler`.
// Aucun FCM, aucun serveur : tout est local, à partir du temps réel Firestore (app ouverte)
// ou du rafraîchissement en arrière-plan (`BackgroundRefresh`).

import Foundation

// MARK: - Contexte d'affichage

/// Ce qu'il faut savoir d'une commande pour rédiger ses notifications.
nonisolated struct GroupOrderNotificationContext: Sendable, Hashable {
    /// « Voisins de Saint-Michel »
    var groupName: String
    /// Produit avec son article, en minuscules : « les pommes de terre jaunes ».
    var productName: String
    /// Unité de prix du produit : « sac de 10 kg ».
    var unit: String
    /// Lot de la commande (paliers, date limite) ; nil si inconnu : pas de prix ni de rappel de date limite.
    var offer: Offer?
    /// Point de cueillette ; nil si inconnu : pas de livraison ni de rappel de cueillette.
    var pickupPoint: PickupPoint?

    /// Contexte au mieux : chaque donnée manquante est remplacée par un libellé neutre.
    static func load(for order: GroupOrder, repositories: AppRepositories) async -> GroupOrderNotificationContext {
        let group = try? await repositories.groups.group(id: order.groupId)
        let offer = try? await repositories.offers.offer(id: order.offerId)
        var product: Product?
        if let offer { product = try? await repositories.vendors.product(id: offer.productId) }
        var pickupPoint: PickupPoint?
        if let id = order.pickupPointId { pickupPoint = try? await repositories.pickupPoints.pickupPoint(id: id) }
        return GroupOrderNotificationContext(
            groupName: group?.name ?? String(localized: "ton groupe"),
            productName: product.map { Self.withArticle($0.name) } ?? String(localized: "ta commande"),
            unit: product?.unit ?? offer?.shareUnit ?? "part",
            offer: offer,
            pickupPoint: pickupPoint
        )
    }

    /// « Pommes de terre jaunes » → « les pommes de terre jaunes », « Riz basmati » → « le riz basmati »,
    /// « Huile d'olive » → « l'huile d'olive ». Le genre n'est pas connu : « le » par défaut.
    static func withArticle(_ name: String) -> String {
        let lower = name.lowercased()
        // L'anglais n'a pas d'article devant « rice » ou « potatoes ».
        if AppLanguage.isEnglish { return lower }
        let firstWord = lower.split(separator: " ").first.map(String.init) ?? lower
        if firstWord.hasSuffix("s") || firstWord.hasSuffix("x") { return "les \(lower)" }
        if let first = lower.first, "aeiouyhàâéèêîôû".contains(first) { return "l'\(lower)" }
        return "le \(lower)"
    }
}

// MARK: - Dernier état connu

/// Dernier état vu de chaque commande (et des lots / parts du ménage), pour ne notifier que les vrais changements,
/// même après une relance de l'app en arrière-plan.
protocol LastKnownStateStore: AnyObject {
    func groupOrder(id: String) -> GroupOrder?
    func save(_ order: GroupOrder)
    func offer(id: String) -> Offer?
    func saveOffers(_ offers: [Offer])
    func share(householdId: String, groupOrderId: String) -> Share?
    func saveShare(_ share: Share, groupOrderId: String)
}

/// Mémoire vive : tests et previews.
final class InMemoryLastKnownStateStore: LastKnownStateStore {
    private var state = LastKnownState()

    init() {}

    func groupOrder(id: String) -> GroupOrder? { state.groupOrders[id] }
    func save(_ order: GroupOrder) { state.groupOrders[order.id] = order }
    func offer(id: String) -> Offer? { state.offers[id] }
    func saveOffers(_ offers: [Offer]) { for offer in offers { state.offers[offer.id] = offer } }
    func share(householdId: String, groupOrderId: String) -> Share? {
        state.shares[LastKnownState.shareKey(householdId, groupOrderId)]
    }
    func saveShare(_ share: Share, groupOrderId: String) {
        state.shares[LastKnownState.shareKey(share.householdId, groupOrderId)] = share
    }
}

/// Petit JSON dans `UserDefaults` : survit aux relances de l'app (rafraîchissement en arrière-plan).
final class UserDefaultsLastKnownStateStore: LastKnownStateStore {
    static let defaultKey = "grenier.notifications.lastKnownState"

    private let defaults: UserDefaults
    private let key: String
    private var state: LastKnownState

    init(defaults: UserDefaults = .standard, key: String = UserDefaultsLastKnownStateStore.defaultKey) {
        self.defaults = defaults
        self.key = key
        state = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LastKnownState.self, from: $0) }
            ?? LastKnownState()
    }

    func groupOrder(id: String) -> GroupOrder? { state.groupOrders[id] }
    func save(_ order: GroupOrder) { mutate { $0.groupOrders[order.id] = order } }
    func offer(id: String) -> Offer? { state.offers[id] }
    func saveOffers(_ offers: [Offer]) { mutate { for offer in offers { $0.offers[offer.id] = offer } } }
    func share(householdId: String, groupOrderId: String) -> Share? {
        state.shares[LastKnownState.shareKey(householdId, groupOrderId)]
    }
    func saveShare(_ share: Share, groupOrderId: String) {
        mutate { $0.shares[LastKnownState.shareKey(share.householdId, groupOrderId)] = share }
    }

    private func mutate(_ change: (inout LastKnownState) -> Void) {
        change(&state)
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }
}

/// Contenu persisté du dernier état connu.
nonisolated struct LastKnownState: Codable, Sendable, Hashable {
    var groupOrders: [String: GroupOrder] = [:]
    var offers: [String: Offer] = [:]
    /// Parts du ménage, par « commande|ménage ».
    var shares: [String: Share] = [:]

    static func shareKey(_ householdId: String, _ groupOrderId: String) -> String { "\(groupOrderId)|\(householdId)" }
}

// MARK: - Coordinateur

/// Transforme les changements de commandes groupées en notifications locales.
///
///     let coordinator = NotificationCoordinator(scheduler: UserNotificationScheduler())
///     await coordinator.handle(order, context: context)            // un nouvel état
///     await coordinator.observe(groupOrderIds: ids, repositories: repositories)  // temps réel, jusqu'à l'annulation
///
/// Première fois qu'une commande est vue : aucune notification immédiate (c'est l'état de base),
/// seulement les rappels à heure connue (cueillette, date limite).
@MainActor
final class NotificationCoordinator {
    private let scheduler: any NotificationScheduler
    private let store: any LastKnownStateStore
    private let now: () -> Date

    init(
        scheduler: any NotificationScheduler,
        store: any LastKnownStateStore = InMemoryLastKnownStateStore(),
        now: @escaping () -> Date = { .now }
    ) {
        self.scheduler = scheduler
        self.store = store
        self.now = now
    }

    // MARK: Diff pur

    /// Notifications immédiates à envoyer pour le passage de `old` à `new` (vide si `old` est nil).
    nonisolated static func events(
        from old: GroupOrder?, to new: GroupOrder, context: GroupOrderNotificationContext
    ) -> [GrenierNotification.Event] {
        guard let old, old != new else { return [] }
        var events: [GrenierNotification.Event] = []
        let tiers = context.offer?.sortedTiers ?? []

        if new.status == .cancelled {
            return old.status == .cancelled ? [] : [.orderCancelled]
        }

        if let index = new.currentTierIndex, index > (old.currentTierIndex ?? -1), tiers.indices.contains(index) {
            events.append(.tierUnlocked(priceCents: tiers[index].priceCents, unit: context.unit))
        }

        if new.status == .closed, old.status == .open || old.status == .reached,
           let index = new.currentTierIndex, tiers.indices.contains(index) {
            events.append(.orderClosed(finalPriceCents: tiers[index].priceCents, unit: context.unit))
        }

        if new.status == .delivered, old.status != .delivered, let point = context.pickupPoint {
            events.append(.deliveryArrived(pickupPointName: point.name))
        }
        return events
    }

    /// Prochain créneau dont le rappel (1 h avant) n'est pas encore passé.
    nonisolated static func nextPickupSlot(of order: GroupOrder, now: Date) -> PickupSlot? {
        order.pickupSlots
            .filter { $0.start.addingTimeInterval(-GrenierNotification.pickupReminderLead) > now }
            .min { $0.start < $1.start }
    }

    // MARK: Nouvel état

    /// Compare au dernier état connu, programme ce qui a changé, puis retient le nouvel état.
    /// Le même état reçu deux fois ne programme rien.
    func handle(_ order: GroupOrder, context: GroupOrderNotificationContext) async {
        let old = store.groupOrder(id: order.id)
        if old == order { return }
        // Retenu AVANT les appels asynchrones : un doublon qui arrive entre-temps ne repasse pas.
        store.save(order)
        await apply(old: old, new: order, context: context)
    }

    private func apply(old: GroupOrder?, new: GroupOrder, context: GroupOrderNotificationContext) async {
        let order = GrenierNotification.Order(
            orderId: new.id, groupId: new.groupId, groupName: context.groupName, productName: context.productName
        )
        let date = now()

        if new.status == .cancelled {
            guard old?.status != .cancelled else { return }
            // Plus de rappels pour une commande annulée ; puis l'annonce (qui ne doit pas être effacée).
            await scheduler.cancelAll(forOrder: new.id)
            if old != nil { await send(.init(order: order, event: .orderCancelled)) }
            return
        }

        for event in Self.events(from: old, to: new, context: context) {
            await send(.init(order: order, event: event))
        }

        await updatePickupReminder(old: old, new: new, order: order, context: context, now: date)
        await updateDeadlineReminder(old: old, new: new, order: order, context: context, now: date)
        // Date limite retenue : un lot prolongé reprogramme son rappel au prochain changement de la commande.
        if let offer = context.offer { store.saveOffers([offer]) }
    }

    // MARK: Rappels à heure connue

    private func updatePickupReminder(
        old: GroupOrder?, new: GroupOrder, order: GrenierNotification.Order,
        context: GroupOrderNotificationContext, now: Date
    ) async {
        // Seulement une fois la commande lancée (minimum atteint) et tant qu'elle n'est pas cueillie.
        let launched: Set<GroupOrder.Status> = [.reached, .closed, .delivered]
        let wanted = launched.contains(new.status) ? Self.nextPickupSlot(of: new, now: now) : nil
        let previous = old.flatMap { launched.contains($0.status) ? Self.nextPickupSlot(of: $0, now: now) : nil }
        let samePoint = old?.pickupPointId == new.pickupPointId
        if old != nil, wanted == previous, samePoint { return }

        guard let slot = wanted, let point = context.pickupPoint else {
            if old != nil { await scheduler.cancel(.pickupReminder, forOrder: new.id) }
            return
        }
        await send(.init(order: order, event: .pickupReminder(pickupPointName: point.name, slot: slot)))
    }

    private func updateDeadlineReminder(
        old: GroupOrder?, new: GroupOrder, order: GrenierNotification.Order,
        context: GroupOrderNotificationContext, now: Date
    ) async {
        let isOpen = { (order: GroupOrder) in order.status == .open || order.status == .reached }
        guard isOpen(new) else {
            if let old, isOpen(old) { await scheduler.cancel(.deadlineReminder, forOrder: new.id) }
            return
        }
        guard let deadline = context.offer?.deadline else { return }
        let previousDeadline = store.offer(id: new.offerId)?.deadline
        if let old, isOpen(old), previousDeadline == nil || previousDeadline == deadline { return }

        let reminder = GrenierNotification(order: order, event: .deadlineReminder(deadline: deadline))
        guard !reminder.isExpired(now: now) else { return }
        await send(reminder)
    }

    /// Programme ; un refus (notifications coupées) est ignoré : rien d'autre à faire sans serveur.
    private func send(_ notification: GrenierNotification) async {
        _ = try? await scheduler.schedule(notification)
    }

    // MARK: Temps réel

    /// Écoute chaque commande avec `observeGroupOrder(id:)` et notifie ses changements.
    /// Revient quand la tâche est annulée (ou que tous les flux se terminent).
    func observe(groupOrderIds: [String], repositories: AppRepositories) async {
        await withTaskGroup(of: Void.self) { group in
            for id in Set(groupOrderIds) {
                group.addTask { await self.observe(groupOrderId: id, repositories: repositories) }
            }
        }
    }

    private func observe(groupOrderId: String, repositories: AppRepositories) async {
        let stream = await repositories.groupOrders.observeGroupOrder(id: groupOrderId)
        var context: GroupOrderNotificationContext?
        var contextPickupPointId: String?
        do {
            for try await order in stream {
                if Task.isCancelled { break }
                if context == nil || contextPickupPointId != order.pickupPointId {
                    context = await GroupOrderNotificationContext.load(for: order, repositories: repositories)
                    contextPickupPointId = order.pickupPointId
                }
                if Task.isCancelled { break }
                if let context { await handle(order, context: context) }
            }
        } catch {
            // Flux terminé en erreur (hors ligne, commande supprimée) : on arrête d'écouter cette commande.
        }
    }
}
