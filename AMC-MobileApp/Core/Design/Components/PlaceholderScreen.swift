import SwiftUI

/// Écran temporaire pour un onglet pas encore construit. À remplacer par le vrai écran (et les maquettes de claude-samuel).
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let message: String
    /// Épic du backlog qui construira l'écran, par exemple « E03 ».
    let epic: String

    var body: some View {
        NavigationStack {
            ScrollView {
                ContentUnavailableView {
                    Label(title, systemImage: systemImage)
                        .symbolRenderingMode(.hierarchical)
                } description: {
                    Text(message)
                } actions: {
                    // `epic` reste pour les développeurs ; jamais affiché (pas de jargon interne à l'écran).
                    Text("Bientôt dans Grenier")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .containerRelativeFrame(.vertical)
            }
            .navigationTitle(title)
            .profileToolbar()
        }
    }
}

#Preview("Clair") {
    PlaceholderScreen(title: "Groupes", systemImage: "person.3.fill", message: "Les groupes de ton quartier.", epic: "E03")
}

#Preview("Sombre") {
    PlaceholderScreen(title: "Groupes", systemImage: "person.3.fill", message: "Les groupes de ton quartier.", epic: "E03")
        .preferredColorScheme(.dark)
}
