// MeasureUnit.swift
// Unité de mesure commune aux envies des familles (`GroupWish`) et aux disponibilités des vendeurs
// (`VendorSupply`), pour que le `Matcher` compare des quantités comparables (S-07, S-08, S-09).

import Foundation

/// Unité d'une quantité. Pas de conversion entre unités : 2 douzaines et 3 kg ne s'additionnent pas.
nonisolated enum MeasureUnit: String, Codable, Sendable, CaseIterable {
    case kilogram = "kg"
    case liter = "l"
    case dozen
    case unit

    /// Libellé court affiché après une quantité, en français.
    var title: String {
        switch self {
        case .kilogram: "kg"
        case .liter: "L"
        case .dozen: "douzaine"
        case .unit: "unité"
        }
    }
}
