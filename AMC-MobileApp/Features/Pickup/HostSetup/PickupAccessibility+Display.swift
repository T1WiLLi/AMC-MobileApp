// PickupAccessibility+Display.swift
// Libellés et SF Symbols des options d'accessibilité d'un point de cueillette (T-077).

import Foundation

extension PickupPoint.Accessibility {
    var title: String {
        switch self {
        case .wheelchair: String(localized: "Accès fauteuil roulant")
        case .stepFree: String(localized: "Sans marche")
        case .elevator: String(localized: "Ascenseur")
        case .nearMetro: String(localized: "Près du métro")
        case .parking: String(localized: "Stationnement")
        }
    }

    var detail: String {
        switch self {
        case .wheelchair: String(localized: "Porte et passage assez larges")
        case .stepFree: String(localized: "Entrée de plain-pied")
        case .elevator: String(localized: "Si la cueillette est à l'étage")
        case .nearMetro: String(localized: "Station à moins de 10 min à pied")
        case .parking: String(localized: "Place pour se garer quelques minutes")
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
