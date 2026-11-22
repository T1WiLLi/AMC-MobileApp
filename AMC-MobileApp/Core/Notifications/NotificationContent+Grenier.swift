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
        /// Rappel programmé 24 h avant la date limite du lot (commande encore ouverte).
        case deadlineReminder(deadline: Date)
    }

    /// Famille d'événement : sert aux identifiants et aux catégories.
    enum Kind: String, Sendable, CaseIterable {
        case tier
        /// Fermeture et annulation partagent le même identifiant : l'une remplace l'autre.
        case outcome
        case delivery
        case pickupReminder
        case deadlineReminder

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
        case .deadlineReminder: .deadlineReminder
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

    /// Avance du rappel de date limite sur la fermeture du lot.
    static let deadlineReminderLead: TimeInterval = 24 * 60 * 60

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
            String(localized: "Palier débloqué à \(order.groupName) !")
        case .orderClosed:
            String(localized: "Commande fermée à \(order.groupName)")
        case .orderCancelled:
            String(localized: "Commande annulée à \(order.groupName)")
        case .deliveryArrived(let pickupPointName):
            String(localized: "C'est arrivé à \(pickupPointName) !")
        case .pickupReminder:
            String(localized: "Cueillette dans 1 h")
        case .deadlineReminder:
            String(localized: "Plus que 24 h à \(order.groupName)")
        }
    }

    /// Corps de la notification. `calendar` fixe le fuseau des heures de cueillette.
    func body(calendar: Calendar = .current) -> String {
        let product = order.productName.capitalizingFirstLetter
        switch event {
        case .tierUnlocked(let priceCents, let unit):
            return String(localized: "\(product) passe à \(Self.unitPrice(priceCents, unit: unit)).")
        case .orderClosed(let finalPriceCents, let unit):
            return String(localized: "Prix final : \(Self.unitPrice(finalPriceCents, unit: unit)). Ton code de cueillette t'attend dans l'app.")
        case .orderCancelled:
            return String(localized: "Le minimum n'a pas été atteint pour \(order.productName). Tu ne paies rien.")
        case .deliveryArrived:
            return String(localized: "\(product) t'attend. Montre ton code QR à la cueillette.")
        case .pickupReminder(let pickupPointName, let slot):
            let start = Self.hour(slot.start, calendar: calendar)
            let end = Self.hour(slot.end, calendar: calendar)
            return String(localized: "\(product) t'attend à \(pickupPointName), de \(start) à \(end).")
        case .deadlineReminder(let deadline):
            let hour = Self.hour(deadline, calendar: calendar)
            return String(localized: "\(product) : la commande ferme demain à \(hour). Invite tes voisins pour faire baisser le prix.")
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
    /// Pour le rappel de cueillette, 1 h avant le créneau ; pour la date limite, 24 h avant
    /// (nil si cette heure est déjà passée).
    func fireDate(now: Date = .now) -> Date? {
        let date: Date
        switch event {
        case .pickupReminder(_, let slot): date = slot.start.addingTimeInterval(-Self.pickupReminderLead)
        case .deadlineReminder(let deadline): date = deadline.addingTimeInterval(-Self.deadlineReminderLead)
        default: return nil
        }
        return date > now ? date : nil
    }

    /// Un rappel n'a plus de sens si son heure est passée (créneau dans moins d'une heure,
    /// fermeture dans moins de 24 h).
    func isExpired(now: Date = .now) -> Bool {
        switch event {
        case .pickupReminder, .deadlineReminder: fireDate(now: now) == nil
        default: false
        }
    }

    /// Déclencheur : calendrier pour les rappels, immédiat (nil) sinon.
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
        return AppLanguage.clockText(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}

private extension String {
    nonisolated var capitalizingFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
