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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
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
