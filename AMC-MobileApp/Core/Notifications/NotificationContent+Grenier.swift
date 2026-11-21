// NotificationContent+Grenier.swift
// Les notifications locales de Grenier (RQ-084) : quoi dire, à qui, et quand.
// Pas de serveur, donc pas de push distant : l'app programme elle-même ces notifications
// quand elle voit changer une commande groupée.

import Foundation
import UserNotifications

/// Une notification Grenier : une commande groupée et l'événement à annoncer.
///
///     let notification = GrenierNotification(
///         order: .init(orderId: "go-riz", groupId: "parc-ex-ouest", groupName: "Parc-Ex Ouest", productName: "le riz"),
///         event: .tierUnlocked(priceCents: 260, unit: "kg")
///     )
///     // « Palier débloqué à Parc-Ex Ouest ! » / « Le riz passe à 2,60 $/kg. »
nonisolated struct GrenierNotification: Sendable, Hashable {
    /// La commande concernée, telle qu'on l'affiche.
    struct Order: Sendable, Hashable {
        var orderId: String
        var groupId: String
        /// Nom du groupe de quartier : « Parc-Ex Ouest ».
        var groupName: String
        /// Produit avec son article, en minuscules : « le riz », « les pommes ».
        var productName: String
    }

    enum Event: Sendable, Hashable {
        /// Un nouveau palier est franchi : le prix par unité baisse.
        case tierUnlocked(priceCents: Cents, unit: String)
        /// La commande est fermée : le prix final est figé.
        case orderClosed(finalPriceCents: Cents, unit: String)
        /// La commande est annulée : le minimum n'a pas été atteint.
        case orderCancelled
        /// La livraison est arrivée au point de cueillette.
        case deliveryArrived(pickupPointName: String)
        /// Rappel programmé 1 h avant le début du créneau de cueillette.
        case pickupReminder(pickupPointName: String, slot: PickupSlot)
    }

    /// Famille d'événement : sert aux identifiants et aux catégories.
    enum Kind: String, Sendable, CaseIterable {
        case tier
        /// Fermeture et annulation partagent le même identifiant : l'une remplace l'autre.
        case outcome
        case delivery
        case pickupReminder

        /// Identifiant stable pour une commande : programmer à nouveau remplace la notification précédente.
        func identifier(forOrder orderId: String) -> String {
            "grenier.order.\(orderId).\(rawValue)"
        }
    }

    var order: Order
    var event: Event

    var kind: Kind {
        switch event {
        case .tierUnlocked: .tier
        case .orderClosed, .orderCancelled: .outcome
        case .deliveryArrived: .delivery
        case .pickupReminder: .pickupReminder
        }
    }

    /// Identifiant stable de la requête : `grenier.order.<id>.<famille>`.
    var identifier: String { kind.identifier(forOrder: order.orderId) }

    /// Les notifications d'un même groupe s'empilent ensemble dans le centre de notifications.
    var threadIdentifier: String { "grenier.group.\(order.groupId)" }

    /// Catégorie, pour brancher plus tard des actions (« Voir mon code », etc.).
    var categoryIdentifier: String { "grenier.\(kind.rawValue)" }

    /// Avance du rappel de cueillette sur le début du créneau.
    static let pickupReminderLead: TimeInterval = 60 * 60

    /// Clés de `userInfo` pour ouvrir le bon écran quand on touche la notification.
    enum UserInfoKey {
        static let orderId = "orderId"
        static let groupId = "groupId"
        static let kind = "kind"
    }
}

// MARK: - Textes

extension GrenierNotification {
    var title: String {
        switch event {
        case .tierUnlocked:
            "Palier débloqué à \(order.groupName) !"
        case .orderClosed:
            "Commande fermée à \(order.groupName)"
        case .orderCancelled:
            "Commande annulée à \(order.groupName)"
        case .deliveryArrived(let pickupPointName):
            "C'est arrivé à \(pickupPointName) !"
        case .pickupReminder:
            "Cueillette dans 1 h"
        }
    }

    /// Corps de la notification. `calendar` fixe le fuseau des heures de cueillette.
    func body(calendar: Calendar = .current) -> String {
        let product = order.productName.capitalizingFirstLetter
        switch event {
        case .tierUnlocked(let priceCents, let unit):
            return "\(product) passe à \(Self.unitPrice(priceCents, unit: unit))."
        case .orderClosed(let finalPriceCents, let unit):
            return "Prix final : \(Self.unitPrice(finalPriceCents, unit: unit)). Ton code de cueillette t'attend dans l'app."
        case .orderCancelled:
            return "Le minimum n'a pas été atteint pour \(order.productName). Tu ne paies rien."
        case .deliveryArrived:
            return "\(product) t'attend. Montre ton code QR à la cueillette."
        case .pickupReminder(let pickupPointName, let slot):
            let start = Self.hour(slot.start, calendar: calendar)
            let end = Self.hour(slot.end, calendar: calendar)
            return "\(product) t'attend à \(pickupPointName), de \(start) à \(end)."
        }
    }

    /// Niveau d'interruption : la cueillette passe le mode Concentration (si l'app a le droit « Time Sensitive »).
    var interruptionLevel: UNNotificationInterruptionLevel {
        if case .pickupReminder = event { .timeSensitive } else { .active }
    }

    /// Contenu prêt pour `UNNotificationRequest`.
    func makeContent(calendar: Calendar = .current) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body(calendar: calendar)
        content.sound = .default
        content.threadIdentifier = threadIdentifier
        content.categoryIdentifier = categoryIdentifier
        content.interruptionLevel = interruptionLevel
        content.userInfo = [
            UserInfoKey.orderId: order.orderId,
            UserInfoKey.groupId: order.groupId,
            UserInfoKey.kind: kind.rawValue
        ]
        return content
    }

    /// Date de livraison prévue : nil pour une notification immédiate.
    /// Pour le rappel de cueillette, 1 h avant le créneau (nil si cette heure est déjà passée).
    func fireDate(now: Date = .now) -> Date? {
        guard case .pickupReminder(_, let slot) = event else { return nil }
        let date = slot.start.addingTimeInterval(-Self.pickupReminderLead)
        return date > now ? date : nil
    }

    /// Le rappel de cueillette n'a plus de sens si le créneau commence dans moins d'une heure.
    func isExpired(now: Date = .now) -> Bool {
        if case .pickupReminder = event { fireDate(now: now) == nil } else { false }
    }

    /// Déclencheur : calendrier pour le rappel de cueillette, immédiat (nil) sinon.
    func makeTrigger(calendar: Calendar = .current, now: Date = .now) -> UNNotificationTrigger? {
        guard let date = fireDate(now: now) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    // MARK: Formatage

    /// « 2,60 $/kg »
    static func unitPrice(_ cents: Cents, unit: String) -> String {
        "\(Money.format(cents))/\(unit)"
    }

    /// Heure à la québécoise : « 17 h », « 17 h 30 ».
    static func hour(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) h" : String(format: "%d h %02d", hour, minute)
    }
}

private extension String {
    nonisolated var capitalizingFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
