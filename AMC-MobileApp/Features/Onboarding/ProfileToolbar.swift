import SwiftUI

/// Bouton Profil en haut à droite de chaque écran racine ; ouvre le profil en feuille.
/// Le profil sort de la barre d'onglets pour garder au plus 4 onglets + Recherche (sinon iOS les replie dans « Autre »).
/// Un appui long (ou le rotor Actions de VoiceOver) ouvre un menu pour changer de portail sans passer par le profil (T-123).
struct ProfileToolbarModifier: ViewModifier {
    @State private var isPresented = false
    @AppStorage(Portal.storageKey) private var portal: Portal = .family
    @Environment(PortalSwitchCoordinator.self) private var portalSwitch: PortalSwitchCoordinator?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if portalSwitch != nil {
                            Picker(selection: portalSelection) {
                                ForEach(Portal.allCases) { item in
                                    Label(item.title, systemImage: item.systemImage).tag(item)
                                }
                            } label: {
                                Label("Changer de portail", systemImage: "arrow.left.arrow.right.circle")
                            }
                            .pickerStyle(.inline)
                        }
                        Button("Ouvrir mon profil", systemImage: "person.crop.circle") {
                            isPresented = true
                        }
                    } label: {
                        Label("Profil", systemImage: "person.crop.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            // Petit rebond au retour de la feuille : le profil « reprend sa place ».
                            .symbolEffect(.bounce, options: .nonRepeating, value: isPresented)
                    } primaryAction: {
                        isPresented = true
                    }
                    .accessibilityHint("Ouvre ton profil. Maintiens le doigt pour changer de portail.")
                }
            }
            .sensoryFeedback(.selection, trigger: isPresented) { _, new in new }
            .sheet(isPresented: $isPresented) {
                ProfileSheet()
            }
    }

    /// Le menu montre le portail actif coché ; en choisir un autre lance la bascule animée.
    private var portalSelection: Binding<Portal> {
        Binding(
            get: { portal },
            set: { newPortal in
                portalSwitch?.switchPortal(from: portal, to: newPortal, reduceMotion: reduceMotion)
            }
        )
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
