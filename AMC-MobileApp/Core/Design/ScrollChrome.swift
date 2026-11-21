import SwiftUI

// Bord de défilement sous la barre de navigation (T-140, spec S-01).
//
// Avec l'effet `.soft` par défaut, le titre en ligne (« Bonjour Amina ») restait posé sur les cartes
// colorées qui passent dessous (carte Économie verte, en-tête du groupe) : illisible. L'effet `.hard`
// d'iOS 26 pose un fond net sous la barre, comme sur les écrans denses d'Apple, tout en gardant
// le verre des boutons de la barre.
//
//     ScrollView { … }
//         .grenierScrollEdge()

extension View {
    /// Bord de défilement de l'app : fond net sous la barre de navigation, pour que le titre reste lisible
    /// sur n'importe quelle carte. À poser sur chaque `ScrollView` / `List` racine d'un écran.
    func grenierScrollEdge() -> some View {
        scrollEdgeEffectStyle(.hard, for: .top)
    }
}
