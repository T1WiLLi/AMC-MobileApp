import SwiftUI

/// Profil commun aux deux portails, avec la bascule de portail (RQ-006).
struct ProfileScreen: View {
    @AppStorage(Portal.storageKey) private var portal: Portal = .family
    /// Optionnel : absent dans les previews et les tests qui n'injectent pas de session.
    @Environment(SessionViewModel.self) private var session: SessionViewModel?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Portail actif", selection: $portal) {
                        ForEach(Portal.allCases) { portal in
                            Label(portal.title, systemImage: portal.systemImage)
                                .tag(portal)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Portail")
                } footer: {
                    Text("Un même compte peut acheter en famille et vendre comme producteur.")
                }

                Section("Compte") {
                    if let user = session?.currentUser {
                        LabeledContent {
                            Text(user.email)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label(user.displayName, systemImage: "person.crop.circle.fill")
                        }
                        Button("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            session?.signOut()
                        }
                    } else {
                        Label("Non connecté", systemImage: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Profil")
            .sensoryFeedback(.selection, trigger: portal)
        }
    }
}

#Preview("Clair") {
    ProfileScreen()
}

#Preview("Sombre") {
    ProfileScreen()
        .preferredColorScheme(.dark)
}

#Preview("Connecté") {
    ProfileScreen()
        .environment(SessionViewModel(auth: FakeAuthService(signedInUser: .sample)))
}
