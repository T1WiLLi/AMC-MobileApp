import SwiftUI

/// Profil commun aux deux portails, avec la bascule de portail (RQ-006).
struct ProfileScreen: View {
    @AppStorage(Portal.storageKey) private var portal: Portal = .family
    @AppStorage(AppTheme.storageKey) private var appTheme: AppTheme = .grenier
    /// Optionnel : absent dans les previews et les tests qui n'injectent pas de session.
    @Environment(SessionViewModel.self) private var session: SessionViewModel?
    /// Optionnel : absent dans les previews sans verrou.
    @Environment(AppLock.self) private var appLock: AppLock?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContext) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bascule animée (T-123) ; absente dans les previews sans `RootView`.
    @Environment(PortalSwitchCoordinator.self) private var portalSwitch: PortalSwitchCoordinator?
    /// Portail touché : la pastille y glisse avant la fermeture de la feuille.
    @State private var pendingPortal: Portal?
    /// T-122 : photo de profil, relue à chaque apparition.
    @State private var photoURL: URL?
    /// FB-06 : nom, photo et suppression du compte modifiés directement ici (session connectée seulement).
    @State private var account: AccountViewModel?
    /// T-159 : demandes pour rejoindre le ménage en attente (propriétaire seulement), pastille sur « Mon ménage ».
    @State private var pendingJoinRequests = 0
    /// Portail vendeur : feuille « Ma vitrine ».
    @State private var showsVendorShop = false
    /// Ouvert en feuille : bouton Fermer dans la barre de l'écran racine seulement
    /// (un bouton superposé à la feuille passait par-dessus « Enregistrer » des écrans poussés).
    var showsCloseButton = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProfileHeader(
                        user: session?.currentUser,
                        portal: pendingPortal ?? portal,
                        photoURL: account?.user != nil ? account?.photoURL : photoURL,
                        savedName: account?.user?.displayName
                    )
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .grenierAppear(index: 0, style: .sheet)
                }

                Section {
                    portalSwitcher
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .grenierAppear(index: 1, style: .sheet)
                } header: {
                    ProfileSectionHeader(String(localized: "Portail"), systemImage: "arrow.left.arrow.right.circle.fill")
                } footer: {
                    Label("Un même compte peut acheter en famille et vendre comme producteur.", systemImage: "person.2.badge.key.fill")
                        .symbolRenderingMode(.hierarchical)
                }

                // T-075 : profil famille (RQ-015, RQ-017 à RQ-020), écrans dans Features/Profile/.
                Section {
                    if portal == .vendor, !appContext.vendorId.isEmpty {
                        // Portail vendeur : la vitrine remplace le ménage, qui ne le concerne pas.
                        Button {
                            showsVendorShop = true
                        } label: {
                            Label {
                                Text("Photos et zones desservies")
                                    .foregroundStyle(Color.texte)
                            } icon: {
                                RowIcon(systemImage: "photo.on.rectangle.angled", tint: .grenier)
                            }
                        }
                        .accessibilityHint("Ouvre ta vitrine : photos, description et zones desservies.")
                    } else {
                        NavigationLink {
                            HouseholdProfileLink()
                        } label: {
                            Label {
                                Text("Mon ménage")
                            } icon: {
                                RowIcon(systemImage: "house.fill", tint: .solidarite)
                            }
                        }
                        .badge(pendingJoinRequests)
                        .accessibilityHint(pendingJoinRequests > 0 ? String(localized: "\(pendingJoinRequests) demande(s) pour rejoindre ton ménage") : "")
                    }
                    NavigationLink {
                        PreferencesLink()
                    } label: {
                        Label {
                            Text("Préférences")
                        } icon: {
                            RowIcon(systemImage: "slider.horizontal.3", tint: .economie)
                        }
                    }
                    // RQ-019 : le mode aîné à portée de main, sans fouiller dans Préférences.
                    SeniorModeToggleRow()
                } header: {
                    switch portal {
                    case .family:
                        ProfileSectionHeader(String(localized: "Ma famille"), systemImage: "figure.2.and.child.holdinghands")
                    case .vendor:
                        ProfileSectionHeader(String(localized: "Ma boutique"), systemImage: "storefront.fill")
                    case .organization:
                        ProfileSectionHeader(String(localized: "Mon organisme"), systemImage: "building.2.fill")
                    }
                }

                if portal == .family {
                    // T-105 (RQ-099, RQ-100) : planificateur de besoins du mois.
                    Section {
                        NavigationLink {
                            NeedsPlannerScreen()
                        } label: {
                            Label {
                                Text("Planifier mon mois")
                            } icon: {
                                RowIcon(systemImage: "list.bullet.clipboard.fill", tint: .economie)
                            }
                        }
                    } footer: {
                        Text("Tes besoins et ton budget, et les lots qui y répondent.")
                    }
                }

                if let appLock {
                    SecuritySection(lock: appLock)
                }

                // B-035 : thèmes interchangeables (accent, fond, coins), aperçu en direct.
                Section {
                    NavigationLink {
                        ThemePickerScreen()
                    } label: {
                        Label {
                            LabeledContent("Thème", value: appTheme.title)
                        } icon: {
                            RowIcon(systemImage: "paintpalette.fill", tint: .grenier)
                        }
                    }
                } header: {
                    ProfileSectionHeader("Apparence", systemImage: "paintbrush.pointed.fill")
                }

                Section {
                    if let user = session?.currentUser {
                        // FB-06 : photo et nom se modifient ici, sans écran « Mon compte » de plus.
                        if let account {
                            AccountEditRows(model: account)
                        }
                        Label {
                            Text(user.email)
                                .foregroundStyle(Color.texteSecondaire)
                                .textSelection(.enabled)
                        } icon: {
                            RowIcon(systemImage: "envelope.fill", tint: .grenier)
                        }
                        .accessibilityLabel("Courriel : \(user.email)")
                        Button(role: .destructive) {
                            session?.signOut()
                        } label: {
                            Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                                .symbolRenderingMode(.hierarchical)
                        }
                    } else {
                        Label {
                            Text("Non connecté")
                                .foregroundStyle(Color.texteSecondaire)
                        } icon: {
                            RowIcon(systemImage: "person.crop.circle.badge.questionmark", tint: .texteSecondaire)
                        }
                    }
                } header: {
                    ProfileSectionHeader(String(localized: "Compte"), systemImage: "person.text.rectangle.fill")
                } footer: {
                    if account != nil {
                        Text("Ta photo et ton nom apparaissent aux membres de ton groupe et à ton point de cueillette.")
                    }
                }

                if session?.currentUser != nil, let account {
                    AccountDeleteSection(model: account, session: session) {
                        ProfileSectionHeader(String(localized: "Zone sensible"), systemImage: "exclamationmark.triangle.fill")
                    }
                }

                Section {
                    // FB-19 : rejoue la visite de Noisette sans redémarrer (voir `GuidedTour`).
                    if portal == .family && GuidedTour.shared.isEnabled {
                        Button {
                            dismiss()
                            // La carte d'accueil se présente une fois la feuille du Profil fermée.
                            Task {
                                try? await Task.sleep(for: .milliseconds(450))
                                GuidedTour.shared.replay()
                            }
                        } label: {
                            Label {
                                Text("Revoir la visite guidée")
                                    .foregroundStyle(Color.texte)
                            } icon: {
                                RowIcon(systemImage: "figure.wave", tint: .grenier)
                            }
                        }
                        .accessibilityHint("\(MascotView.name) te remontre l'app, en commençant par l'Accueil")
                    }
                    // Geste caché (RQ-114) : 5 taps ou appui long ouvrent les outils de démo.
                    AppVersionLabel()
                        .demoToolsTrigger()
                } header: {
                    ProfileSectionHeader(String(localized: "À propos"), systemImage: "basket.fill")
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .grenierBackground()
            .navigationTitle("Profil")
            .sheet(isPresented: $showsVendorShop) {
                VendorProfileScreen(repositories: appContext.repositories, vendorId: appContext.vendorId)
                    .presentationDetents([.large])
            }
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
                    }
                }
            }
            .onAppear {
                if account == nil, let session, session.currentUser != nil {
                    account = AccountViewModel(
                        repositories: appContext.repositories, userId: appContext.userId, auth: session.auth
                    )
                }
                Task { photoURL = try? await appContext.repositories.users.user(id: appContext.userId).photoURL }
                Task {
                    guard appContext.hasHousehold else { return }
                    pendingJoinRequests = (try? await appContext.repositories.users
                        .joinRequests(ofHousehold: appContext.householdId, byUserId: appContext.userId).count) ?? 0
                }
            }
        }
        // B-035 : la feuille ouverte suit le thème choisi en direct.
        .appThemed()
    }

    /// Capsule de verre « Familles | Vendeurs » (T-123) et la promesse du portail choisi.
    private var portalSwitcher: some View {
        let shown = pendingPortal ?? portal
        return VStack(alignment: .leading, spacing: 12) {
            PortalSegmentedControl(selection: shown) { switchPortal(to: $0) }
            Label {
                Text(shown.detail)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: shown.systemImage)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            }
            .font(.subheadline)
            .foregroundStyle(Color.texteSecondaire)
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, 4)
            .grenierAnimation(.smooth, value: shown)
        }
    }

    /// La pastille glisse tout de suite, puis la feuille se ferme pendant que le voile de bascule
    /// se répand derrière elle (`PortalSwitchCoordinator`, qui change le portail une fois l'écran couvert).
    /// Basculer d'abord détruirait la barre d'onglets qui présente la feuille : elle disparaîtrait d'un coup.
    private func switchPortal(to newPortal: Portal) {
        guard newPortal != portal, pendingPortal == nil else { return }
        withGrenierAnimation(.snappy, reduceMotion: reduceMotion) { pendingPortal = newPortal }
        Task { @MainActor in
            // Le temps de voir la pastille arriver sur le nouveau portail.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 220))
            if let portalSwitch {
                dismiss()
                if !portalSwitch.switchPortal(from: portal, to: newPortal, reduceMotion: reduceMotion) {
                    pendingPortal = nil
                }
            } else {
                // Sans coordinateur (previews) : ancienne bascule directe.
                dismiss()
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 400))
                withAnimation(reduceMotion ? nil : .smooth) { portal = newPortal }
                pendingPortal = nil
            }
        }
    }
}

// MARK: - En-tête

/// Carte d'identité en tête du profil : avatar à l'initiale, nom, courriel et portail actif.
private struct ProfileHeader: View {
    let user: AuthUser?
    let portal: Portal
    /// T-122 : photo de `AppUser`, nil = initiales.
    var photoURL: URL? = nil
    /// FB-06 : nom enregistré dans la section Compte (sinon celui de la session).
    var savedName: String? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var scaledAvatar: CGFloat = 84
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private var avatarSide: CGFloat { min(scaledAvatar, 128) }

    var body: some View {
        VStack(spacing: 12) {
            if let user {
                avatar(for: user)
                VStack(spacing: 4) {
                    Text(savedName ?? user.displayName)
                        .font(.title2.bold())
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.texte)
                        .multilineTextAlignment(.center)
                    Label(user.email, systemImage: "envelope.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                        .multilineTextAlignment(.center)
                }
            } else {
                GrenierSymbolScene(
                    symbol: "person.crop.circle.fill",
                    satellites: Portal.allCases.map { .init($0.systemImage, tint: $0.tint) }
                )
                Text("Ton profil LeGrenier")
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.texte)
            }

            Label("Portail \(portal.title)", systemImage: portal.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.onAccent)
                .contentTransition(.symbolEffect(.replace))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.grenier, in: .capsule)
                .animation(reduceMotion ? nil : .smooth, value: portal)
                .accessibilityLabel("Portail actif : \(portal.title)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(Color.surface, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .onAppear { hasAppeared = true }
    }

    private func avatar(for user: AuthUser) -> some View {
        // T-122 : photo de profil (users/{uid}/media/avatar), sinon initiales.
        AvatarView(name: savedName ?? user.displayName, photoURL: photoURL, size: avatarSide)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: avatarSide * 0.26))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.onAccent, Color.economie)
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : hasAppeared)
                    .opacity(user.isEmailVerified ? 1 : 0)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Petits composants

/// En-tête de section de formulaire avec icône teintée.
private struct ProfileSectionHeader: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.grenier)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Icône de ligne : SF Symbol hiérarchique teinté, sans tuile de fond (FB-07),
/// pour que toutes les lignes du profil s'alignent comme les `Label` natifs.
private struct RowIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .accessibilityHidden(true)
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
                Label {
                    Text("Verrouiller avec \(lock.biometry.title)")
                } icon: {
                    Image(systemName: lock.biometry.systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(lock.isEnabled ? Color.economie : Color.grenier)
                        .symbolEffect(.bounce, value: lock.isEnabled)
                }
            }
            .tint(.grenier)
            .disabled(isWorking || !lock.biometry.canAuthenticate)
            .sensoryFeedback(.success, trigger: lock.isEnabled) { _, new in new }
            if let error = lock.lastError {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.texteSecondaire)
            }
        } header: {
            ProfileSectionHeader(String(localized: "Sécurité"), systemImage: "lock.shield.fill")
        } footer: {
            Label(
                lock.biometry.canAuthenticate
                    ? String(localized: "LeGrenier se verrouille quand tu quittes l'app. Ton code de cueillette et tes paiements restent protégés.")
                    : String(localized: "Configure Face ID ou un code dans les Réglages de l'iPhone pour activer le verrou."),
                systemImage: lock.isEnabled ? "lock.fill" : "lock.open.fill"
            )
            .symbolRenderingMode(.hierarchical)
            .contentTransition(.symbolEffect(.replace))
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

#Preview("Connecté sombre AX5") {
    ProfileScreen()
        .environment(SessionViewModel(auth: FakeAuthService(signedInUser: .sample)))
        .environment(\.dynamicTypeSize, .accessibility5)
        .preferredColorScheme(.dark)
}
