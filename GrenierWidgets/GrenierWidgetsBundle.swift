// GrenierWidgetsBundle.swift
// Extension GrenierWidgets : Live Activity de la commande (RQ-085) et widget « prochain palier » (RQ-086).

import SwiftUI
import WidgetKit

@main
struct GrenierWidgetsBundle: WidgetBundle {
    var body: some Widget {
        OrderLiveActivity()
        NextTierWidget()
    }
}

/// Couleurs Grenier de l'extension (copie des couleurs de l'app dans GrenierWidgets/Assets.xcassets).
enum GrenierPalette {
    static let accent = Color("AccentColor")
    static let economie = Color("Economie")
    static let fond = Color("Fond")
    static let surface = Color("Surface")
    static let piste = Color("Piste")
    static let texte = Color("Texte")
    static let texteSecondaire = Color("TexteSecondaire")
}
