import SwiftUI

/// Profil commun aux deux portails, avec la bascule de portail (RQ-006).
struct ProfileScreen: View {
    @AppStorage(Portal.storageKey) private var portal: Portal = .family
    /// Optionnel : absent dans les previews et les tests qui n'injectent pas de session.
    @Environment(SessionViewModel.self) private var session: SessionViewModel?
    /// Optionnel : absent dans les previews sans verrou.
    @Environment(AppLock.self) private var appLock: AppLock?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Portail touché, pour l'haptique (part avant la fermeture de la feuille).
    @State private var pendingPortal: Portal?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    portalCards
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Portail")
                } footer: {
                    Text("Un même compte peut acheter en famille et vendre comme producteur.")
                }

                // T-075 : profil famille (RQ-015, RQ-017 à RQ-020), écrans dans Features/Profile/.
                Section("Ma famille") {
                    NavigationLink {
                        HouseholdProfileLink()
                    } label: {
                        Label("Mon ménage", systemImage: "house.fill")
                    }
                    NavigationLink {
                        PreferencesLink()
                    } label: {
                        Label("Préférences", systemImage: "slider.horizontal.3")
                    }
                }

                if portal == .family {
                    // T-105 (RQ-099, RQ-100) : planificateur de besoins du mois.
                    Section {
                        NavigationLink {
                            NeedsPlannerScreen()
                        } label: {
                            Label("Planifier mon mois", systemImage: "list.bullet.clipboard.fill")
                                .symbolRenderingMode(.hierarchical)
                        }
                    } footer: {
                        Text("Tes besoins et ton budget, et les lots qui y répondent.")
                    }
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

                Section {
                    // Geste caché (RQ-114) : 5 taps ou appui long ouvrent les outils de démo.
                    AppVersionLabel()
                        .demoToolsTrigger()
                }
            }
            .navigationTitle("Profil")
            .sensoryFeedback(.selection, trigger: pendingPortal) { _, new in new != nil }
        }
    }

    /// Cartes compactes côte à côte, empilées sous Dynamic Type accessibilité.
    private var portalCards: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            ForEach(Portal.allCases) { item in
                PortalCard(portal: item, isSelected: (pendingPortal ?? portal) == item, size: .compact) {
                    switchPortal(to: item)
                }
            }
        }
        // Deux cartes de même hauteur côte à côte.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Haptique et coche tout de suite, puis fermeture animée de la feuille, puis bascule.
    /// Basculer d'abord détruirait la barre d'onglets qui présente la feuille : elle disparaîtrait d'un coup.
    private func switchPortal(to newPortal: Portal) {
        guard newPortal != portal, pendingPortal == nil else { return }
        withAnimation(.smooth) { pendingPortal = newPortal }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            dismiss()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 400))
            withAnimation(reduceMotion ? nil : .smooth) {
                portal = newPortal
            }
            pendingPortal = nil
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
