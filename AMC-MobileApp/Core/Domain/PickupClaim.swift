// PickupClaim.swift
// T-173 (FB-22) : un seul membre du ménage récupère une cueillette. Le premier qui dit « Je m'en occupe »
// l'emporte (transaction côté Firestore) ; les autres voient « Ta famille récupère déjà cette cueillette par X ».

import Foundation

/// Règles pures de l'engagement à récupérer une part (`Share.pickupClaimedBy`). Partagées par les dépôts Fake et Firestore.
nonisolated enum PickupClaim {
    /// Où en est la part pour le membre `userId`.
    enum State: Sendable, Hashable {
        /// Personne ne s'en occupe encore.
        case open
        /// Le membre connecté s'en occupe.
        case mine
        /// Un autre membre du ménage s'en occupe (uid).
        case takenBy(String)
        /// Déjà récupérée : plus rien à réserver.
        case pickedUp
    }

    /// Résultat d'un « Je m'en occupe ».
    enum Outcome: Sendable, Hashable {
        /// Engagement posé (ou déjà le sien) : la part à jour.
        case claimed(Share)
        /// Un autre membre est passé avant (uid) : rien n'est écrit.
        case takenBy(String)
        /// Part déjà récupérée : rien n'est écrit.
        case alreadyPickedUp
    }

    static func state(of share: Share, for userId: String) -> State {
        if share.isPickedUp { return .pickedUp }
        guard let claimer = share.pickupClaimedBy, !claimer.isEmpty else { return .open }
        return claimer == userId ? .mine : .takenBy(claimer)
    }

    /// Premier arrivé, premier servi : on ne remplace jamais l'engagement d'un autre membre.
    static func claim(_ share: Share, by userId: String, at date: Date) -> Outcome {
        switch state(of: share, for: userId) {
        case .pickedUp: return .alreadyPickedUp
        case .takenBy(let other): return .takenBy(other)
        case .mine: return .claimed(share)
        case .open:
            var share = share
            share.pickupClaimedBy = userId
            share.pickupClaimedAt = date
            return .claimed(share)
        }
    }

    /// « Je ne peux plus » : seul le membre engagé se retire, et seulement avant la remise. `nil` sinon.
    static func releasing(_ share: Share, by userId: String) -> Share? {
        guard state(of: share, for: userId) == .mine else { return nil }
        var share = share
        share.pickupClaimedBy = nil
        share.pickupClaimedAt = nil
        return share
    }

    /// « Ta famille récupère déjà cette cueillette par Amina. » (sans prénom connu : « par un autre membre »).
    static func takenMessage(claimerName: String?) -> String {
        let name = claimerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
            ? String(localized: "Ta famille récupère déjà cette cueillette par un autre membre.")
            : String(localized: "Ta famille récupère déjà cette cueillette par \(name).")
    }
}
