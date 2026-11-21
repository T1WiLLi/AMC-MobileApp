import SwiftUI

/// Bouton Profil en haut à droite de chaque écran racine ; ouvre le profil en feuille.
/// Le profil sort de la barre d'onglets pour garder au plus 4 onglets + Recherche (sinon iOS les replie dans « Autre »).
struct ProfileToolbarModifier: ViewModifier {
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Profil", systemImage: "person.crop.circle") {
                        isPresented = true
                    }
                }
            }
            .sheet(isPresented: $isPresented) {
                ProfileScreen()
                    .presentationDetents([.medium, .large])
            }
    }
}

extension View {
    func profileToolbar() -> some View {
        modifier(ProfileToolbarModifier())
    }
}
