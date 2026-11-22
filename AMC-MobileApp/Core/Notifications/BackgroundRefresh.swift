// BackgroundRefresh.swift
// Rafraîchissement en arrière-plan (T-107, S-05 / S-10 / S-12) : sans serveur ni push distant, iOS réveille
// l'app de temps en temps (BGAppRefreshTask) ; on recharge les lots actifs, les commandes groupées du ménage
// et ses parts (ce qui réchauffe aussi le cache Firestore), on compare au dernier état connu et le
// `NotificationCoordinator` programme les notifications locales (palier atteint, commande fermée…).

import BackgroundTasks
import Foundation

// MARK: - Enveloppes testables de BGTaskScheduler

/// Une tâche d'arrière-plan lancée par le système.
protocol BackgroundRefreshTask: AnyObject {
    /// Appelé par le système (sur une file quelconque) quand le temps accordé est écoulé.
    var expirationHandler: (@Sendable () -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

/// Ce que l'app utilise de `BGTaskScheduler`.
protocol BackgroundTaskScheduling: AnyObject {
    /// Enregistre le gestionnaire ; à faire avant la fin du lancement de l'app.
    func register(identifier: String, launchHandler: @escaping @MainActor (any BackgroundRefreshTask) -> Void) -> Bool
    /// Demande au système une prochaine exécution, au plus tôt à `earliestBeginDate`.
    func submit(identifier: String, earliestBeginDate: Date?) throws
}

/// Implémentation système.
final class SystemBackgroundTaskScheduler: BackgroundTaskScheduling {
    private let scheduler: BGTaskScheduler

    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }

    func register(identifier: String, launchHandler: @escaping @MainActor (any BackgroundRefreshTask) -> Void) -> Bool {
        // File principale : le gestionnaire s'exécute sur le MainActor.
        scheduler.register(forTaskWithIdentifier: identifier, using: .main) { task in
            let wrapped = SystemBackgroundRefreshTask(task)
            MainActor.assumeIsolated { launchHandler(wrapped) }
        }
    }

    func submit(identifier: String, earliestBeginDate: Date?) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try scheduler.submit(request)
    }
}

/// `BGTask` derrière le protocole. Le système autorise ces appels depuis n'importe quelle file.
nonisolated private final class SystemBackgroundRefreshTask: BackgroundRefreshTask, @unchecked Sendable {
    private let task: BGTask
    /// Copie `@Sendable` du gestionnaire confié à `task` : `BGTask.expirationHandler` n'est pas typé `@Sendable`,
    /// le relire depuis la tâche système demanderait une conversion non sûre.
    private var sendableExpirationHandler: (@Sendable () -> Void)?

    init(_ task: BGTask) {
        self.task = task
    }

    var expirationHandler: (@Sendable () -> Void)? {
        get { sendableExpirationHandler }
        set {
            sendableExpirationHandler = newValue
            task.expirationHandler = newValue
        }
    }

    func setTaskCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}

// MARK: - Rafraîchissement

/// Rafraîchit en arrière-plan et passe les changements au coordinateur de notifications.
///
///     let refresh = BackgroundRefresh(coordinator: coordinator, repositories: repositories, householdId: { id })
///     refresh.register()   // au lancement
///     refresh.schedule()   // puis à chaque exécution
@MainActor
final class BackgroundRefresh {
    /// Doit figurer dans `BGTaskSchedulerPermittedIdentifiers` de l'Info.plist.
    static let identifier = "ca.amc2026.mobileapp.refresh"
    /// Délai minimal demandé entre deux exécutions (iOS décide du moment réel).
    static let minimumInterval: TimeInterval = 15 * 60

    private let taskScheduler: any BackgroundTaskScheduling
    private let coordinator: NotificationCoordinator
    private let repositories: () -> AppRepositories
    private let store: any LastKnownStateStore
    private let householdId: () -> String?
    private let now: () -> Date

    init(
        taskScheduler: any BackgroundTaskScheduling = SystemBackgroundTaskScheduler(),
        coordinator: NotificationCoordinator,
        repositories: @autoclosure @escaping () -> AppRepositories,
        store: any LastKnownStateStore,
        householdId: @escaping () -> String?,
        now: @escaping () -> Date = { .now }
    ) {
        self.taskScheduler = taskScheduler
        self.coordinator = coordinator
        self.repositories = repositories
        self.store = store
        self.householdId = householdId
        self.now = now
    }

    /// Enregistre le gestionnaire auprès du système. Une seule fois, pendant le lancement.
    @discardableResult
    func register() -> Bool {
        taskScheduler.register(identifier: Self.identifier) { [self] task in
            handle(task)
        }
    }

    /// Demande la prochaine exécution. Échec ignoré (simulateur, Actualisation en arrière-plan coupée).
    func schedule() {
        try? taskScheduler.submit(
            identifier: Self.identifier, earliestBeginDate: now().addingTimeInterval(Self.minimumInterval)
        )
    }

    /// Gestionnaire système : reprogramme, rafraîchit, puis signale la fin (ou s'arrête à l'expiration).
    func handle(_ task: any BackgroundRefreshTask) {
        schedule()
        let work = Task { await refresh() }
        task.expirationHandler = { work.cancel() }
        Task {
            let success = await work.value
            task.setTaskCompleted(success: success && !work.isCancelled)
        }
    }

    /// Recharge les lots actifs, les commandes du ménage et ses parts, puis passe chaque commande au coordinateur.
    /// Renvoie `false` si le chargement a échoué (hors ligne…) ou a été interrompu.
    func refresh() async -> Bool {
        let repositories = repositories()
        guard let householdId = householdId() else { return true }
        do {
            let offers = try await repositories.offers.activeOffers(inZone: nil)
            let groups = try await repositories.groups.groups(ofHousehold: householdId)
            for group in groups {
                try Task.checkCancellation()
                for order in try await repositories.groupOrders.groupOrders(ofGroup: group.id) {
                    let shares = try await repositories.groupOrders.shares(ofGroupOrder: order.id)
                    guard let share = shares.first(where: { $0.householdId == householdId }) else { continue }
                    let context = await GroupOrderNotificationContext.load(for: order, repositories: repositories)
                    await coordinator.handle(order, context: context)
                    store.saveShare(share, groupOrderId: order.id)
                }
            }
            // Après le coordinateur : il compare la date limite connue à la nouvelle.
            store.saveOffers(offers)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
