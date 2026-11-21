import PhotosUI
import SwiftUI

/// « Mon compte » (T-103, RQ-021) : photo et nom affiché, puis suppression du compte en deux confirmations.
/// Ouvert depuis la section Compte de `ProfileScreen`.
struct AccountScreen: View {
    @State private var model: AccountViewModel
    /// Optionnel : absent dans les previews (« Se reconnecter » déconnecte la session).
    @Environment(SessionViewModel.self) private var session: SessionViewModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pickedItem: PhotosPickerItem?
    /// Premier temps de la suppression.
    @State private var isConfirmingFirstStep = false
    @FocusState private var isNameFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 96

    init(model: AccountViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        StateView(state: model.loadState, retry: { await model.load() }) { _ in
            form
        }
        .navigationTitle("Mon compte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    isNameFocused = false
                    Task { await model.save() }
                } label: {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Text("Enregistrer")
                    }
                }
                .disabled(!model.canSave)
                .accessibilityHint("Enregistre ton nom et ta photo")
            }
        }
        .task { if model.user == nil { await model.load() } }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await addPhoto(from: item) }
        }
        .grenierHaptic(.success, trigger: model.saveCount) { old, new in new > old }
        .grenierHaptic(.warning, trigger: isConfirmingFirstStep) { _, new in new }
        .grenierHaptic(.error, trigger: model.deletionState) { _, new in
            if case .failed = new { true } else { new == .needsReauthentication }
        }
        .grenierHaptic(.success, trigger: model.deletionState) { _, new in new == .deleted }
        .modifier(DeletionDialogs(model: model, session: session, isConfirmingFirstStep: $isConfirmingFirstStep))
    }
}

/// Confirmations et alertes de la suppression, sorties de `body` : la chaîne entière dépassait
/// le temps de vérification de types du compilateur (« unable to type-check this expression »).
private struct DeletionDialogs: ViewModifier {
    let model: AccountViewModel
    let session: SessionViewModel?
    @Binding var isConfirmingFirstStep: Bool

    func body(content: Content) -> some View {
        content
        // Premier temps : on explique ce qui disparaît.
        .confirmationDialog(
            "Supprimer ton compte ?",
            isPresented: $isConfirmingFirstStep,
            titleVisibility: .visible
        ) {
            Button("Continuer", role: .destructive) { model.requestDeletion() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ton profil et ta place dans le ménage seront effacés. Ton ménage et ses commandes restent pour les autres membres.")
        }
        // Second temps : suppression définitive.
        .confirmationDialog(
            "Dernière confirmation",
            isPresented: Binding(
                get: { model.deletionState == .confirming },
                set: { if !$0 { model.cancelDeletion() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer définitivement", role: .destructive) {
                Task { await model.confirmDeletion() }
            }
            Button("Garder mon compte", role: .cancel) { model.cancelDeletion() }
        } message: {
            Text("C'est irréversible : tu ne pourras pas récupérer ce compte.")
        }
        .alert("Reconnecte-toi d'abord", isPresented: Binding(
            get: { model.deletionState == .needsReauthentication },
            set: { if !$0 { model.dismissDeletionMessage() } }
        )) {
            Button("Se reconnecter") { session?.signOut() }
            Button("Plus tard", role: .cancel) { model.dismissDeletionMessage() }
        } message: {
            Text("Pour protéger ton compte, Grenier demande une connexion récente avant de le supprimer. Reconnecte-toi, puis reviens ici.")
        }
        .alert("Suppression impossible", isPresented: Binding(
            get: { if case .failed = model.deletionState { true } else { false } },
            set: { if !$0 { model.dismissDeletionMessage() } }
        )) {
            Button("OK", role: .cancel) { model.dismissDeletionMessage() }
        } message: {
            if case .failed(let message) = model.deletionState { Text(message) }
        }
    }
}

extension AccountScreen {
    private var form: some View {
        Form {
            photoSection
            nameSection
            deleteSection
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(model.isDeleting)
    }

    // MARK: - Photo

    private var photoSection: some View {
        Section {
            VStack(spacing: 16) {
                avatar
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .grenierSmooth, value: model.photoURL)

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                        Label(model.photoURL == nil ? "Ajouter une photo" : "Changer", systemImage: "camera.fill")
                    }
                    .buttonStyle(.glass)
                    .disabled(model.isAddingPhoto)

                    if model.photoURL != nil {
                        Button("Retirer", systemImage: "trash", role: .destructive) {
                            withAnimation(reduceMotion ? nil : .grenierSmooth) { model.removePhoto() }
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        } footer: {
            Text("Ta photo et ton nom apparaissent aux membres de ton groupe et à ton point de cueillette.")
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    private var avatar: some View {
        ZStack {
            // T-122 : photo (Firestore, démo ou fichier) en fondu, sinon initiales.
            AvatarView(name: model.trimmedDisplayName, photoURL: model.photoURL, size: avatarSize)
            if model.isAddingPhoto {
                Circle().fill(.ultraThinMaterial).overlay { ProgressView() }
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(.circle)
        .overlay(alignment: .bottomTrailing) {
            if model.saveCount > 0, !model.hasChanges {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.onAccent, Color.economie)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : model.saveCount)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(model.photoURL == nil ? "Avatar avec tes initiales, \(model.initials)" : "Ta photo de profil")
        .accessibilityAddTraits(.isImage)
    }

    private func addPhoto(from item: PhotosPickerItem) async {
        defer { pickedItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await model.setPhoto(data: data)
    }

    // MARK: - Nom

    private var nameSection: some View {
        Section {
            TextField("Prénom et nom", text: $model.displayName)
                .textContentType(.name)
                .submitLabel(.done)
                .focused($isNameFocused)
                .onSubmit { Task { await model.save() } }
                .accessibilityLabel("Nom affiché")
            if let error = model.displayNameError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
            if let saveError = model.saveError {
                Label(saveError.message, systemImage: saveError.systemImage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Label("Nom affiché", systemImage: "person.text.rectangle")
        } footer: {
            HStack {
                Text("Le nom que voient tes voisins.")
                Spacer()
                Text("\(model.trimmedDisplayName.count) / \(AccountViewModel.displayNameMaxLength)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(model.trimmedDisplayName.count) caractères sur \(AccountViewModel.displayNameMaxLength)")
            }
        }
        .animation(reduceMotion ? nil : .grenierSmooth, value: model.displayNameError)
    }

    // MARK: - Suppression

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingFirstStep = true
            } label: {
                HStack {
                    Label("Supprimer mon compte", systemImage: "person.crop.circle.badge.xmark")
                    Spacer()
                    if model.isDeleting { ProgressView() }
                }
            }
            .accessibilityHint("Demande deux confirmations avant d'effacer ton compte")
        } header: {
            Label("Zone sensible", systemImage: "exclamationmark.triangle.fill")
        } footer: {
            Text("Efface ton profil, te retire de ton ménage et supprime ton compte de connexion. C'est irréversible.")
        }
    }
}

// MARK: - Previews

private func previewModel(error: AuthError? = nil) -> AccountViewModel {
    let context = AppContext.instant
    let auth = FakeAuthService(signedInUser: .sample, nextError: error, latency: .milliseconds(600))
    return AccountViewModel(repositories: context.repositories, userId: context.userId, auth: auth)
}

#Preview("Clair") {
    NavigationStack { AccountScreen(model: previewModel()) }
}

#Preview("Sombre") {
    NavigationStack { AccountScreen(model: previewModel()) }
        .preferredColorScheme(.dark)
}

#Preview("Reconnexion requise") {
    NavigationStack { AccountScreen(model: previewModel(error: .requiresRecentLogin)) }
}

#Preview("AX5") {
    NavigationStack { AccountScreen(model: previewModel()) }
        .dynamicTypeSize(.accessibility5)
}
