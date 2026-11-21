// GrenierOrderAttributes.swift
// Partagé par l'app (démarrage, mises à jour) et l'extension GrenierWidgets (affichage).
// Aucun accès à Core/ : l'extension ne compile que ce dossier et le sien.

import ActivityKit
import Foundation

/// Live Activity d'une commande groupée (RQ-085) : du palier qui tombe jusqu'à la cueillette.
nonisolated struct GrenierOrderAttributes: ActivityAttributes, Hashable, Sendable {
    /// Palier de prix du lot : à partir de `minFamilies` familles, le prix est `priceCents` par unité.
    nonisolated struct Tier: Codable, Hashable, Sendable {
        var minFamilies: Int
        var priceCents: Int
    }

    /// Étapes de la commande, dans l'ordre.
    nonisolated enum Stage: String, Codable, Hashable, Sendable, CaseIterable {
        /// Le groupe se remplit ; le prochain palier n'est pas encore atteint.
        case ouverte
        /// Un palier vient de tomber : le prix baisse pour tout le groupe.
        case palierFranchi
        /// La commande est partie de chez le vendeur.
        case enRoute
        /// La commande est au point de cueillette.
        case arrivee
        /// La famille a récupéré sa part.
        case recuperee
    }

    /// Ce qui change pendant la vie de l'activité.
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var stage: Stage
        /// Familles engagées dans le groupe.
        var committedFamilies: Int
        /// Seuil (en familles) du prochain palier, nil si le dernier palier est atteint.
        var nextThreshold: Int?
        /// Prix courant par unité, en cents.
        var currentPriceCents: Int
        /// Début du créneau de cueillette.
        var pickupTime: Date
    }

    // MARK: - Statique

    /// « Parc-Ex Ouest »
    var groupName: String
    /// « Riz basmati »
    var productName: String
    /// « Ferme Lafleur »
    var vendorName: String
    /// « Chez Fatima »
    var pickupPlaceName: String
    /// « 7420 rue Ogilvy »
    var pickupAddress: String
    /// Prénom de l'hôte du point de cueillette (« Fatima »).
    var pickupHost: String
    /// Unité de prix : « kg ».
    var unit: String
    /// Part de la famille : « 10 kg ».
    var shareLabel: String
    /// Code de la commande montré à l'hôte : « GRN-4821 ».
    var orderCode: String
    /// Paliers du lot, triés ou non.
    var tiers: [Tier]
}

// MARK: - Données de démo (maquettes F1–F5)

nonisolated extension GrenierOrderAttributes {
    /// Commande d'Amina : riz basmati de la Ferme Lafleur, groupe Parc-Ex Ouest, cueillette chez Fatima.
    static let demo = GrenierOrderAttributes(
        groupName: "Parc-Ex Ouest",
        productName: "Riz basmati",
        vendorName: "Ferme Lafleur",
        pickupPlaceName: "Chez Fatima",
        pickupAddress: "7420 rue Ogilvy",
        pickupHost: "Fatima",
        unit: "kg",
        shareLabel: "10 kg",
        orderCode: "GRN-4821",
        tiers: [
            Tier(minFamilies: 1, priceCents: 320),
            Tier(minFamilies: 11, priceCents: 260),
            Tier(minFamilies: 26, priceCents: 210),
        ]
    )

    /// Prochaine cueillette de démo : aujourd'hui à 17 h (ou demain si 17 h est passé de plus d'une heure).
    static func demoPickupTime(now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now
        if today.addingTimeInterval(3600) < now {
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
        return today
    }
}

nonisolated extension GrenierOrderAttributes.ContentState {
    /// État de démo pour une étape, cohérent avec les paliers de `GrenierOrderAttributes.demo`.
    /// `ouverte` = 25 familles (encore 1 pour −19 %), puis Amina est la 26e famille.
    static func demo(_ stage: GrenierOrderAttributes.Stage, pickupTime: Date = GrenierOrderAttributes.demoPickupTime())
        -> GrenierOrderAttributes.ContentState {
        switch stage {
        case .ouverte:
            GrenierOrderAttributes.ContentState(stage: .ouverte, committedFamilies: 25, nextThreshold: 26,
                                                currentPriceCents: 260, pickupTime: pickupTime)
        case .palierFranchi, .enRoute, .arrivee, .recuperee:
            GrenierOrderAttributes.ContentState(stage: stage, committedFamilies: 26, nextThreshold: nil,
                                                currentPriceCents: 210, pickupTime: pickupTime)
        }
    }

    /// Enchaînement du mode démo devant le jury : palier franchi → en route → arrivée.
    static let demoSequence: [GrenierOrderAttributes.Stage] = [.ouverte, .palierFranchi, .enRoute, .arrivee]
}
