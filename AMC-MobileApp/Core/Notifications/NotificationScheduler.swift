// NotificationScheduler.swift
// Programmation des notifications locales (RQ-084). L'autorisation se demande en contexte,
// via `requestAuthorization()`, jamais au lancement de l'app.

import Foundation
import UserNotifications

/// État de l'autorisation, simplifié pour l'interface.
enum NotificationAuthorizationStatus: Sendable, Equatable {
    /// Jamais demandé : on peut montrer la carte « Activer ».
    case notDetermined
    /// Autorisé (y compris provisoire ou éphémère).
    case authorized
    /// Refusé ou coupé dans Réglages : seul Réglages peut le rallumer.
    case denied

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized, .provisional, .ephemeral: self = .authorized
        case .denied: self = .denied
        @unknown default: self = .denied
        }
    }
}

extension AppError {
    /// L'utilisateur a refusé les notifications, ou les a coupées dans Réglages.
    static let notificationsDenied = AppError.permissionDenied
}

/// Programme et annule les notifications locales de Grenier.
/// Les erreurs levées sont toujours des `AppError` (`.permissionDenied` si refusé ou désactivé).
protocol NotificationScheduler: AnyObject {
    /// État actuel, sans rien demander à l'utilisateur.
    func authorizationStatus() async -> NotificationAuthorizationStatus

    /// Affiche la demande système. À appeler seulement après un geste de l'utilisateur (« Activer »).
    /// Lève `.permissionDenied` si l'utilisateur refuse ou si c'est déjà coupé dans Réglages.
    @discardableResult
    func requestAuthorization() async throws -> NotificationAuthorizationStatus

    /// Programme (ou remplace, même identifiant) une notification.
    /// Renvoie `false` sans rien programmer si le rappel de cueillette est déjà dépassé.
    /// Lève `.permissionDenied` si les notifications ne sont pas autorisées.
    @discardableResult
    func schedule(_ notification: GrenierNotification) async throws -> Bool

    /// Retire une notification d'une commande (en attente et déjà affichée).
    func cancel(_ kind: GrenierNotification.Kind, forOrder orderId: String) async

    /// Retire toutes les notifications d'une commande (quitter le groupe, commande supprimée…).
    func cancelAll(forOrder orderId: String) async
}

// MARK: - Implémentation système

/// Implémentation sur `UNUserNotificationCenter`.
final class UserNotificationScheduler: NotificationScheduler {
    private let center: UNUserNotificationCenter
    private let calendar: Calendar
    private let now: () -> Date

    init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.center = center
        self.calendar = calendar
        self.now = now
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        return NotificationAuthorizationStatus(settings.authorizationStatus)
    }

    @discardableResult
    func requestAuthorization() async throws -> NotificationAuthorizationStatus {
        let current = await authorizationStatus()
        switch current {
        case .authorized: return .authorized
        case .denied: throw AppError.notificationsDenied
        case .notDetermined: break
        }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { throw AppError.notificationsDenied }
            return .authorized
        } catch {
            throw AppError(error)
        }
    }

    @discardableResult
    func schedule(_ notification: GrenierNotification) async throws -> Bool {
        let date = now()
        if notification.isExpired(now: date) {
            await cancel(notification.kind, forOrder: notification.order.orderId)
            return false
        }
        guard await authorizationStatus() == .authorized else { throw AppError.notificationsDenied }

        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: notification.makeContent(calendar: calendar),
            trigger: notification.makeTrigger(calendar: calendar, now: date)
        )
        do {
            try await center.add(request)
            return true
        } catch {
            throw AppError(error)
        }
    }

    func cancel(_ kind: GrenierNotification.Kind, forOrder orderId: String) async {
        remove([kind.identifier(forOrder: orderId)])
    }

    func cancelAll(forOrder orderId: String) async {
        remove(GrenierNotification.Kind.allCases.map { $0.identifier(forOrder: orderId) })
    }

    private func remove(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

// MARK: - Fake

/// Faux planificateur pour les tests et les previews : garde tout en mémoire.
final class FakeNotificationScheduler: NotificationScheduler {
    /// État simulé de l'autorisation.
    var status: NotificationAuthorizationStatus
    /// Réponse simulée de l'utilisateur à la demande système.
    var grantsOnRequest: Bool
    /// Date courante simulée (pour le rappel de cueillette).
    var now: Date

    /// Notifications programmées, par identifiant (une seule par identifiant, comme le système).
    private(set) var scheduled: [String: GrenierNotification] = [:]
    /// Nombre de fois où la demande système a été affichée.
    private(set) var requestCount = 0

    init(status: NotificationAuthorizationStatus = .notDetermined, grantsOnRequest: Bool = true, now: Date = .now) {
        self.status = status
        self.grantsOnRequest = grantsOnRequest
        self.now = now
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus { status }

    @discardableResult
    func requestAuthorization() async throws -> NotificationAuthorizationStatus {
        switch status {
        case .authorized: return .authorized
        case .denied: throw AppError.notificationsDenied
        case .notDetermined:
            requestCount += 1
            status = grantsOnRequest ? .authorized : .denied
            guard grantsOnRequest else { throw AppError.notificationsDenied }
            return .authorized
        }
    }

    @discardableResult
    func schedule(_ notification: GrenierNotification) async throws -> Bool {
        if notification.isExpired(now: now) {
            scheduled[notification.identifier] = nil
            return false
        }
        guard status == .authorized else { throw AppError.notificationsDenied }
        scheduled[notification.identifier] = notification
        return true
    }

    func cancel(_ kind: GrenierNotification.Kind, forOrder orderId: String) async {
        scheduled[kind.identifier(forOrder: orderId)] = nil
    }

    func cancelAll(forOrder orderId: String) async {
        for kind in GrenierNotification.Kind.allCases {
            scheduled[kind.identifier(forOrder: orderId)] = nil
        }
    }
}
