import SwiftUI

/// Dernière étape de l'arrivée (S-03, T-127) : charge le contexte de la personne connectée
/// (ménage, groupe, vendeur depuis Firestore), puis montre l'app avec ce contexte dans l'environnement.
/// Squelette pendant le chargement, erreur avec « Réessayer » si la lecture échoue : jamais d'id de démo.
struct SessionContextGate: View {
    let user: AuthUser

    /// Contexte de base injecté par l'app : dépôts live non résolus (Firebase) ou démo déjà résolue (`.fake`).
    @Environment(\.appContext) private var base
    @Environment(SessionContextStore.self) private var injectedStore: SessionContextStore?
    /// Previews et tests : un store local quand l'app n'en injecte pas.
    @State private var localStore = SessionContextStore()

    private var store: SessionContextStore { injectedStore ?? localStore }

    var body: some View {
        Group {
            switch store.phase {
            case .ready:
                RootView()
                    .environment(\.appContext, store.context)
                    .transition(.opacity)
            case .failed(let error):
                ErrorStateView(error: error) { await store.reload() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .grenierBackground()
                    .transition(.opacity)
            case .idle, .loading:
                SessionLoadingView()
                    .transition(.opacity)
            }
        }
        .grenierAnimation(.smooth, value: store.phase)
        .environment(store)
        .task(id: user.id) { await store.load(for: user, base: base) }
    }
}

/// Squelette de l'app pendant la lecture du profil : la forme d'un accueil, en `.redacted`.
struct SessionLoadingView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Groupe du quartier")
                                .font(.headline)
                            Text("Une commande groupée en cours près de chez toi")
                                .font(.subheadline)
                            Text("12 ménages · 3 lots ouverts")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.background, in: .rect(cornerRadius: 20))
                    }
                }
                .padding()
            }
            .redacted(reason: .placeholder)
            .navigationTitle("LeGrenier")
            .grenierBackground()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement de ton profil")
    }
}

#Preview("Chargement") {
    SessionLoadingView()
}

#Preview("Démo résolue") {
    SessionContextGate(user: .sample)
        .environment(\.appContext, .instant)
        .environment(NetworkMonitor(startsMonitoring: false))
}
