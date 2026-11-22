// ShareActivity.swift
// Signal « une part a changé » (réservation, modification, annulation) pour les écrans qui résument les lots.
// La fiche du lot l'émet ; l'Accueil l'observe et recharge son flux, même s'il est sous la fiche dans la pile
// (le prix et « Encore N parts » de la carte sont à jour au retour, sans attendre un `onAppear`).
//
//     .onChange(of: ShareActivity.shared.generation) { … recharger … }

import Observation

@Observable
@MainActor
final class ShareActivity {
    static let shared = ShareActivity()

    /// +1 à chaque part enregistrée.
    private(set) var generation = 0

    func shareDidChange() {
        generation += 1
    }
}
