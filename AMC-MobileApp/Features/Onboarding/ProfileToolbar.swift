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
                ProfileSheet()
            }
    }
}

/// Feuille Profil : grande d'emblée (rien ne sort de l'écran à AX5), fond crème, bouton Fermer dans la barre.
private struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ProfileScreen()
            // ProfileScreen a sa propre NavigationStack : un ToolbarItem posé d'ici n'y apparaît pas.
            // Le bouton se superpose donc à l'emplacement de la barre, en verre comme un bouton de barre.
            .overlay(alignment: .topTrailing) {
                Button("Fermer", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            }
            .scrollContentBackground(.hidden)
            .presentationBackground(Color.fond)
            .presentationDetents([.large])
    }
}

extension View {
    func profileToolbar() -> some View {
        modifier(ProfileToolbarModifier())
    }
}

#Preview("Clair") {
    NavigationStack {
        Text("Accueil")
            .profileToolbar()
    }
}

#Preview("Feuille") {
    ProfileSheet()
}

#Preview("Feuille sombre") {
    ProfileSheet()
        .preferredColorScheme(.dark)
}
