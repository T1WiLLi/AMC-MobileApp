// HouseholdJoinNotifier.swift
// T-173 (FB-22) : le propriétaire d'un ménage apprend qu'un compte veut le rejoindre, sans serveur :
// notification locale quand une nouvelle demande apparaît (temps réel app ouverte, `BackgroundRefresh` sinon).

import Foundation
import UserNotifications

/// Règles pures des notifications de demande d'adhésion au ménage.
nonisolated enum HouseholdJoinAlerts {
    /// Demandes en attente pas encore annoncées (une demande refusée puis refaite redevient nouvelle).
    static func fresh(_ pending: [HouseholdJoinRequest], seen: Set<String>) -> [HouseholdJoinRequest] {
        pending.filter { $0.status == .pending && !seen.contains($0.userId) }
    }

    /// Identifiant stable : une même demande ne s'affiche qu'une fois.
    static func identifier(householdId: String, userId: String) -> String {
        "grenier.household.\(householdId).join.\(userId)"
    }

    static func title(for request: HouseholdJoinRequest) -> String {
        String(localized: "Nouvelle demande pour ton ménage")
    }

    static func body(for request: HouseholdJoinRequest) -> String {
        let name = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(localized: "\(name.isEmpty ? String(localized: "Quelqu'un") : name) veut rejoindre ton ménage. Accepte ou refuse dans Profil › Mon ménage.")
    }
}

/// Affiche (ou retire) la notification d'une demande. Sans autorisation, ne fait rien : jamais de demande ici.
protocol JoinRequestNotificationPosting: AnyObject {
    func post(_ request: HouseholdJoinRequest) async
    func withdraw(identifiers: [String]) async
}

/// Implémentation système.
final class UserJoinRequestNotificationPoster: JoinRequestNotificationPosting {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func post(_ request: HouseholdJoinRequest) async {
        let settings = await center.notificationSettings()
        guard NotificationAuthorizationStatus(settings.authorizationStatus) == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = HouseholdJoinAlerts.title(for: request)
        content.body = HouseholdJoinAlerts.body(for: request)
        content.sound = .default
        content.threadIdentifier = "grenier.household.\(request.householdId)"
        content.categoryIdentifier = "grenier.householdJoin"
        content.userInfo = ["householdId": request.householdId, "userId": request.userId, "kind": "householdJoin"]
        let identifier = HouseholdJoinAlerts.identifier(householdId: request.householdId, userId: request.userId)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func withdraw(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// Compare les demandes en attente aux dernières vues (par ménage, dans `UserDefaults`) et notifie les nouvelles.
@MainActor
final class HouseholdJoinNotifier {
    private let poster: any JoinRequestNotificationPosting
    private let defaults: UserDefaults

    init(poster: any JoinRequestNotificationPosting = UserJoinRequestNotificationPoster(), defaults: UserDefaults = .standard) {
        self.poster = poster
        self.defaults = defaults
    }

    static func seenKey(householdId: String) -> String { "grenier.household.\(householdId).seenJoinRequests" }

    /// Nouvel état des demandes en attente de `householdId` : notifie les nouvelles, retire celles qui ne sont
    /// plus en attente (acceptées, refusées, annulées). Le même état reçu deux fois ne notifie rien.
    func handle(pending: [HouseholdJoinRequest], householdId: String) async {
        let key = Self.seenKey(householdId: householdId)
        let seen = Set(defaults.stringArray(forKey: key) ?? [])
        let current = Set(pending.filter { $0.status == .pending }.map(\.userId))
        let fresh = HouseholdJoinAlerts.fresh(pending, seen: seen)
        // Retenu AVANT les appels asynchrones : un doublon qui arrive entre-temps ne repasse pas.
        defaults.set(current.sorted(), forKey: key)
        for request in fresh { await poster.post(request) }
        let gone = seen.subtracting(current).map { HouseholdJoinAlerts.identifier(householdId: householdId, userId: $0) }
        await poster.withdraw(identifiers: gone.sorted())
    }
}

// MARK: - Temps réel du ménage partagé

/// T-173 : tant que l'app est ouverte, suit le ménage partagé en temps réel.
/// - groupes du ménage : un autre membre rejoint ou quitte un groupe → `onGroupsChanged` (relire le contexte) ;
/// - demandes d'adhésion (propriétaire seulement) → `HouseholdJoinNotifier`.
@MainActor
enum HouseholdLiveSync {
    /// Revient quand la tâche est annulée (changement de compte, de ménage, déconnexion).
    static func run(
        repositories: AppRepositories, householdId: String, userId: String,
        notifier: HouseholdJoinNotifier, onGroupsChanged: @escaping @MainActor () async -> Void
    ) async {
        guard !householdId.isEmpty, !userId.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await observeGroups(repositories: repositories, householdId: householdId, onChange: onGroupsChanged)
            }
            group.addTask { @MainActor in
                await observeJoinRequests(repositories: repositories, householdId: householdId, userId: userId,
                                          notifier: notifier)
            }
        }
    }

    /// La première valeur est l'état de base (déjà dans le contexte) : seuls les changements suivants comptent.
    private static func observeGroups(
        repositories: AppRepositories, householdId: String, onChange: @escaping @MainActor () async -> Void
    ) async {
        var known: [String]?
        do {
            for try await ids in await repositories.groups.observeGroupIds(ofHousehold: householdId) {
                if Task.isCancelled { break }
                let previous = known
                known = ids
                if let previous, previous != ids { await onChange() }
            }
        } catch {
            // Hors ligne, règles : le retour au premier plan relit quand même le contexte (RootView).
        }
    }

    private static func observeJoinRequests(
        repositories: AppRepositories, householdId: String, userId: String, notifier: HouseholdJoinNotifier
    ) async {
        // Seul le propriétaire lit les demandes : on ne lance pas une écoute que les règles refuseraient.
        guard let household = try? await repositories.users.household(id: householdId),
              HouseholdMembership.isOwner(userId, of: household) else { return }
        do {
            for try await pending in await repositories.users.observeJoinRequests(ofHousehold: householdId, byUserId: userId) {
                if Task.isCancelled { break }
                await notifier.handle(pending: pending, householdId: householdId)
            }
        } catch {
            // Écoute coupée (hors ligne, plus propriétaire) : le rafraîchissement en arrière-plan prend le relais.
        }
    }
}
