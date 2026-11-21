// AutoRefreshState.swift
// Rechargement automatique (S-10, T-090) : quand l'app doit-elle redemander les données ?
// Logique pure (sans réseau ni SwiftUI) pour être testée ; `NetworkMonitor` l'alimente.

import Foundation

/// État du rechargement automatique : connexion, passages en arrière-plan et compteur de rechargements.
///
/// Un rechargement est demandé (le compteur `generation` augmente) :
/// - au retour au premier plan, après un vrai passage en arrière-plan (pas pour un simple `.inactive`,
///   comme le Centre de contrôle), et seulement si l'appareil est en ligne ;
/// - au retour du réseau, après une coupure.
/// Deux demandes rapprochées (retour au premier plan qui rétablit aussi le Wi-Fi) n'en font qu'une.
nonisolated struct AutoRefreshState: Sendable, Equatable {
    /// Pourquoi un rechargement est demandé.
    enum Reason: Sendable, Equatable {
        case foreground
        case reconnected
    }

    /// Phase de l'app, indépendante de SwiftUI (`ScenePhase`) pour les tests.
    enum Phase: Sendable, Equatable {
        case active
        case inactive
        case background
    }

    /// Délai sous lequel deux demandes de rechargement sont fusionnées.
    static let coalescingInterval: TimeInterval = 2

    /// Augmente de 1 à chaque rechargement demandé ; les écrans comparent avec la dernière valeur vue.
    private(set) var generation = 0
    private(set) var lastReason: Reason?
    private(set) var isOnline: Bool
    private var wentToBackground = false
    private var lastRefreshDate: Date?

    /// En ligne par défaut : pas de bandeau « Hors ligne » qui clignote au lancement avant la première mesure.
    init(isOnline: Bool = true) {
        self.isOnline = isOnline
    }

    /// Change de phase ; renvoie la raison si un rechargement est demandé.
    @discardableResult
    mutating func phaseChanged(to phase: Phase, at now: Date) -> Reason? {
        switch phase {
        case .background:
            wentToBackground = true
            return nil
        case .inactive:
            return nil
        case .active:
            guard wentToBackground else { return nil }
            wentToBackground = false
            // Hors ligne : rien à recharger, le retour du réseau s'en chargera.
            guard isOnline else { return nil }
            return requestRefresh(.foreground, at: now)
        }
    }

    /// Change l'état de la connexion ; renvoie la raison si un rechargement est demandé.
    @discardableResult
    mutating func connectivityChanged(isOnline online: Bool, at now: Date) -> Reason? {
        guard online != isOnline else { return nil }
        isOnline = online
        return online ? requestRefresh(.reconnected, at: now) : nil
    }

    private mutating func requestRefresh(_ reason: Reason, at now: Date) -> Reason? {
        if let lastRefreshDate, now.timeIntervalSince(lastRefreshDate) < Self.coalescingInterval {
            return nil
        }
        lastRefreshDate = now
        lastReason = reason
        generation += 1
        return reason
    }

    /// true si un écran qui a déjà traité `lastHandled` doit recharger pour `current`.
    /// `nil` (première apparition de l'écran) : non, son `.task` initial vient déjà de charger.
    static func shouldRefresh(lastHandled: Int?, current: Int) -> Bool {
        guard let lastHandled else { return false }
        return current != lastHandled
    }
}
