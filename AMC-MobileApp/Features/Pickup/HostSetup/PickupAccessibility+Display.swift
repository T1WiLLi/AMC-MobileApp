// PickupAccessibility+Display.swift
// Libellés et SF Symbols des options d'accessibilité d'un point de cueillette (T-077).

import Foundation

extension PickupPoint.Accessibility {
    var title: String {
        switch self {
        case .wheelchair: "Accès fauteuil roulant"
        case .stepFree: "Sans marche"
        case .elevator: "Ascenseur"
        case .nearMetro: "Près du métro"
        case .parking: "Stationnement"
        }
    }

    var detail: String {
        switch self {
        case .wheelchair: "Porte et passage assez larges"
        case .stepFree: "Entrée de plain-pied"
        case .elevator: "Si la cueillette est à l'étage"
        case .nearMetro: "Station à moins de 10 min à pied"
        case .parking: "Place pour se garer quelques minutes"
        }
    }

    var systemImage: String {
        switch self {
        case .wheelchair: "figure.roll"
        case .stepFree: "figure.walk"
        case .elevator: "arrow.up.arrow.down.square.fill"
        case .nearMetro: "tram.fill"
        case .parking: "parkingsign.circle.fill"
        }
    }
}
