import Foundation
import Observation
import UserNotifications

/// Notifications locales touchées (T-107) : ouvre l'écran de la commande concernée.
///
/// `NotificationContent+Grenier` écrit `orderId`, `groupId` et `kind` dans `userInfo` ; `NotificationDelegate`
/// les lit quand on touche la notification et les confie ici. Comme `InviteLinkRouter`, la destination reste
/// en attente tant qu'aucun écran ne l'a prise : `FamilyTabView` choisit l'onglet, `GroupsScreen` pousse la fiche.
@MainActor
@Observable
final class NotificationRouter {
    enum Destination: Hashable, Sendable {
        /// Cueillette : rappel du créneau ou livraison arrivée au point de cueillette.
        case pickup
        /// Palier, fermeture, annulation, date limite : la fiche du groupe de la commande.
        case group(id: String)
    }

    /// Destination reçue et pas encore ouverte.
    private(set) var pendingDestination: Destination?

    func open(_ destination: Destination?) {
        guard let destination else { return }
        pendingDestination = destination
    }

    /// L'onglet Cueillette a été ouvert : rien d'autre à pousser.
    func consumePickup() {
        if pendingDestination == .pickup { pendingDestination = nil }
    }

    /// Prend le groupe en attente, une seule fois.
    func consumeGroup() -> String? {
        guard case .group(let id) = pendingDestination else { return nil }
        pendingDestination = nil
        return id
    }

    /// Lit le `userInfo` écrit par `GrenierNotification.makeContent` ; nil s'il ne vient pas de l'app.
    nonisolated static func destination(userInfo: [AnyHashable: Any]) -> Destination? {
        typealias Key = GrenierNotification.UserInfoKey
        guard let rawKind = userInfo[Key.kind] as? String,
              let kind = GrenierNotification.Kind(rawValue: rawKind) else { return nil }
        switch kind {
        case .delivery, .pickupReminder:
            return .pickup
        case .tier, .outcome, .deadlineReminder:
            guard let groupId = userInfo[Key.groupId] as? String, !groupId.isEmpty else { return nil }
            return .group(id: groupId)
        }
    }
}

/// Délégué du centre de notifications, posé au lancement (`AMCMobileApp.init`) : sans lui, iOS n'affiche
/// aucune notification quand l'app est ouverte, et toucher une notification ne fait qu'ouvrir l'app.
nonisolated final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let router: NotificationRouter

    init(router: NotificationRouter) {
        self.router = router
    }

    /// App au premier plan : la bannière s'affiche quand même (palier franchi, livraison arrivée…).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let destination = NotificationRouter.destination(userInfo: response.notification.request.content.userInfo)
        await router.open(destination)
    }
}
