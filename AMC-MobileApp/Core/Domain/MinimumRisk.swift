// MinimumRisk.swift
// Mise en garde quand le minimum de lancement d'un lot risque de ne pas être atteint avant la date limite (RQ-050, T-104).
// Swift pur, sans UI : projette la vitesse d'engagement des parts à la date limite et la compare à
// `Offer.minimumSharesToLaunch`. Le badge `MinimumRiskBadge` (Core/Design/Components) affiche le résultat.

import Foundation

nonisolated enum MinimumRisk {
    /// Niveau de risque, du plus rassurant au plus inquiétant.
    enum Level: Int, Sendable, Comparable, CaseIterable {
        /// Minimum atteint, commande fermée, ou rythme largement suffisant : pas de badge.
        case none
        /// Le rythme suffit tout juste, ou il est trop tôt pour juger.
        case low
        /// Au rythme actuel, le minimum ne sera pas atteint (ou la date limite est passée).
        case high

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Assessment: Sendable, Equatable {
        var level: Level
        /// Parts qui manquent pour atteindre le minimum de lancement (0 si atteint).
        var missingShares: Int
        /// Parts engagées projetées à la date limite au rythme actuel.
        var projectedShares: Int
        /// Temps restant avant la date limite (0 si passée).
        var timeRemaining: TimeInterval
        /// « Encore 6 parts en 2 jours : partage la commande » ; nil quand le niveau est `.none`.
        var message: String?
    }

    /// Durée de collecte supposée quand on ne connaît pas l'ouverture de la commande (une semaine, comme
    /// `OfferLifecycle.defaultRecurrenceInterval`).
    static let defaultCollectionDuration: TimeInterval = 7 * 24 * 3600
    /// Marge au-dessus du minimum pour considérer le rythme confortable (20 %).
    static let comfortMargin = 1.2
    /// Avant cette part de la collecte écoulée, un rythme insuffisant n'est qu'un risque faible : trop tôt pour juger.
    static let earlyFraction = 0.15

    /// Évalue le risque que `order` n'atteigne pas `offer.minimumSharesToLaunch` avant `offer.deadline`.
    /// - Parameter openedAt: ouverture de la commande, pour calculer la vitesse d'engagement.
    ///   Nil : `defaultCollectionDuration` avant la date limite.
    static func assess(offer: Offer, order: GroupOrder, now: Date = .now, openedAt: Date? = nil) -> Assessment {
        let committed = max(0, order.committedShares)
        let missing = max(0, offer.minimumSharesToLaunch - committed)
        let remaining = max(0, offer.deadline.timeIntervalSince(now))

        func result(_ level: Level, projected: Int, message: String?) -> Assessment {
            Assessment(level: level, missingShares: missing, projectedShares: projected,
                       timeRemaining: remaining, message: level == .none ? nil : message)
        }

        // Minimum atteint ou commande déjà fermée : la clôture (ClosurePolicy) prend le relais.
        guard TierEngine.isOpen(order),
              !TierEngine.progress(offer: offer, committedShares: committed).isLaunchable else {
            return result(.none, projected: committed, message: nil)
        }

        // Date limite passée, commande encore ouverte sous le minimum : elle sera annulée à la clôture.
        guard remaining > 0 else {
            return result(.high, projected: committed,
                          message: "Date limite passée : il manquait \(FrenchPlural.count(missing, "part"))")
        }

        let start = min(openedAt ?? offer.deadline.addingTimeInterval(-defaultCollectionDuration), now)
        let total = offer.deadline.timeIntervalSince(start)
        let elapsed = now.timeIntervalSince(start)
        // Durée plancher (début de collecte, au moins une heure) pour ne pas extrapoler une seule réservation en flèche.
        let rate = Double(committed) / max(elapsed, total * earlyFraction, 3600)
        let projected = committed + Int((rate * remaining).rounded(.down))

        let level: Level
        if Double(projected) >= Double(offer.minimumSharesToLaunch) * comfortMargin {
            level = .none
        } else if projected >= offer.minimumSharesToLaunch || (total > 0 && elapsed / total < earlyFraction) {
            level = .low
        } else {
            level = .high
        }

        let lead = "Encore \(FrenchPlural.count(missing, "part")) \(durationPhrase(remaining))"
        let advice = level == .high ? "partage la commande" : "invite tes voisins"
        return result(level, projected: projected, message: "\(lead) : \(advice)")
    }

    /// « en 2 jours », « en 5 heures », « en moins d'une heure ».
    static func durationPhrase(_ interval: TimeInterval) -> String {
        let hours = Int(interval / 3600)
        if hours >= 24 { return "en " + FrenchPlural.count(hours / 24, "jour") }
        if hours >= 1 { return "en " + FrenchPlural.count(hours, "heure") }
        return "en moins d'une heure"
    }
}
