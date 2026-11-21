import SwiftUI

/// Profil commun aux deux portails, avec la bascule de portail (RQ-006).
struct ProfileScreen: View {
    @AppStorage(Portal.storageKey) private var portal: Portal = .family
    /// Optionnel : absent dans les previews et les tests qui n'injectent pas de session.
    @Environment(SessionViewModel.self) private var session: SessionViewModel?
    /// Optionnel : absent dans les previews sans verrou.
    @Environment(AppLock.self) private var appLock: AppLock?

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

                if let appLock {
                    SecuritySection(lock: appLock)
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

/// Section « Sécurité » : activer ou couper le verrou Face ID.
private struct SecuritySection: View {
    let lock: AppLock
    @State private var isWorking = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { lock.isEnabled },
                set: { newValue in
                    Task {
                        isWorking = true
                        if newValue { _ = await lock.enable() } else { lock.disable() }
                        isWorking = false
                    }
                }
            )) {
                Label("Verrouiller avec \(lock.biometry.title)", systemImage: lock.biometry.systemImage)
            }
            .disabled(isWorking || !lock.biometry.canAuthenticate)
            if let error = lock.lastError {
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Sécurité")
        } footer: {
            Text(lock.biometry.canAuthenticate
                 ? "Grenier se verrouille quand tu quittes l'app. Ton code de cueillette et tes paiements restent protégés."
                 : "Configure Face ID ou un code dans les Réglages de l'iPhone pour activer le verrou.")
        }
    }
}

#Preview("Clair") {
    ProfileScreen()
}

#Preview("Avec verrou") {
    ProfileScreen()
        .environment(AppLock(authenticator: FakeBiometricAuthenticator(), defaults: UserDefaults(suiteName: "preview-profile")!))
}

#Preview("Sombre") {
    ProfileScreen()
        .preferredColorScheme(.dark)
}

#Preview("Connecté") {
    ProfileScreen()
        .environment(SessionViewModel(auth: FakeAuthService(signedInUser: .sample)))
}
