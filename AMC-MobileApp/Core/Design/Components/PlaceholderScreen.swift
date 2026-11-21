import SwiftUI

/// Écran temporaire pour un onglet pas encore construit : un texte produit, sans jargon interne.
/// Fond crème `Fond`, et rien ne se coupe aux tailles d'accessibilité (le contenu défile au besoin).
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let message: String

    @State private var visibleHeight: CGFloat = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, systemImage: String, message: String) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }

    /// Ancienne signature : l'épic n'est plus affiché. Garde la compilation des écrans encore en cours de réécriture.
    init(title: String, systemImage: String, message: String, epic: String) {
        self.init(title: title, systemImage: systemImage, message: message)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ContentUnavailableView {
                    VStack(spacing: 12) {
                        StateIllustration(systemImage: systemImage)
                            .symbolEffect(.bounce, value: appeared && !reduceMotion)
                        Text(title)
                            .font(.title2.bold())
                            .foregroundStyle(.texte)
                    }
                } description: {
                    Text(message)
                } actions: {
                    Label("Ça arrive très bientôt.", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                        .multilineTextAlignment(.center)
                }
                .onAppear { appeared = true }
                // Hauteur minimale = zone visible : centré quand ça tient, défile quand ça déborde (AX5).
                .frame(maxWidth: .infinity, minHeight: visibleHeight)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            } action: { _, height in
                visibleHeight = max(height, 0)
            }
            .grenierBackground()
            .navigationTitle(title)
            .profileToolbar()
        }
    }
}

#Preview("Clair") {
    PlaceholderScreen(title: "Groupes", systemImage: "person.3.fill", message: "Les groupes d'achat de ton quartier.")
}

#Preview("Sombre") {
    PlaceholderScreen(title: "Groupes", systemImage: "person.3.fill", message: "Les groupes d'achat de ton quartier.")
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    PlaceholderScreen(title: "Impact", systemImage: "leaf.fill", message: "Ce que ton quartier économise, mois après mois.")
        .dynamicTypeSize(.accessibility5)
}
