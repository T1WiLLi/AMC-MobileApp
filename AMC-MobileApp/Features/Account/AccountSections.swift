import PhotosUI
import SwiftUI

// « Mon compte » (T-103, RQ-021, FB-06) : photo, nom affiché et suppression du compte,
// directement dans les réglages (`ProfileScreen`), sans écran de plus.

/// Lignes « photo » et « nom affiché » à poser dans la section Compte d'un `Form`.
/// Le bouton « Enregistrer » n'apparaît que lorsqu'il y a des changements.
struct AccountEditRows: View {
    @Bindable var model: AccountViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pickedItem: PhotosPickerItem?
    @FocusState private var isNameFocused: Bool
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 60

    var body: some View {
        Group {
            switch model.loadState {
            case .loaded:
                photoRow
                nameRow
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
                if model.hasChanges {
                    saveRow
                        .transition(.opacity)
                }
            case .failed(let error):
                Label(error.message, systemImage: error.systemImage)
                    .foregroundStyle(Color.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
                Button("Réessayer", systemImage: "arrow.clockwise") {
                    Task { await model.load() }
                }
            case .idle, .loading, .empty:
                Label("Prénom et nom", systemImage: "person.text.rectangle.fill")
                    .redacted(reason: .placeholder)
                    .accessibilityLabel("Chargement de ton compte")
            }
        }
        .disabled(model.isDeleting)
        .symbolRenderingMode(.hierarchical)
        .animation(reduceMotion ? nil : .grenierSmooth, value: model.hasChanges)
        .animation(reduceMotion ? nil : .grenierSmooth, value: model.displayNameError)
        .task { if model.user == nil { await model.load() } }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await addPhoto(from: item) }
        }
        .grenierHaptic(.success, trigger: model.saveCount) { old, new in new > old }
    }

    // MARK: - Photo

    private var photoRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        // Calculé hors du libellé du PhotosPicker : sa closure est Sendable (pas d'accès au modèle MainActor).
        let pickerTitle = model.photoURL == nil ? String(localized: "Ajouter une photo") : String(localized: "Changer la photo")
        return layout {
            avatar
            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                    Label(pickerTitle, systemImage: "camera.fill")
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
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
        .contentTransition(.opacity)
        .animation(reduceMotion ? nil : .grenierSmooth, value: model.photoURL)
        .overlay(alignment: .bottomTrailing) {
            if model.saveCount > 0, !model.hasChanges {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.onAccent, Color.economie)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : model.saveCount)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(model.photoURL == nil ? String(localized: "Avatar avec tes initiales, \(model.initials)") : String(localized: "Ta photo de profil"))
        .accessibilityAddTraits(.isImage)
    }

    private func addPhoto(from item: PhotosPickerItem) async {
        defer { pickedItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await model.setPhoto(data: data)
    }

    // MARK: - Nom

    private var nameRow: some View {
        Label {
            HStack {
                TextField("Prénom et nom", text: $model.displayName)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { Task { await model.save() } }
                    .accessibilityLabel("Nom affiché")
                Text("\(model.trimmedDisplayName.count) / \(AccountViewModel.displayNameMaxLength)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.texteSecondaire)
                    .contentTransition(.numericText())
                    .opacity(isNameFocused ? 1 : 0)
                    .accessibilityLabel("\(model.trimmedDisplayName.count) caractères sur \(AccountViewModel.displayNameMaxLength)")
            }
        } icon: {
            Image(systemName: "person.text.rectangle.fill")
                .foregroundStyle(Color.grenier)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Enregistrer

    private var saveRow: some View {
        HStack(spacing: 12) {
            Button("Annuler", role: .cancel) {
                isNameFocused = false
                withAnimation(reduceMotion ? nil : .grenierSmooth) { model.discardChanges() }
            }
            .buttonStyle(.glass)
            Spacer(minLength: 0)
            Button {
                isNameFocused = false
                Task { await model.save() }
            } label: {
                if model.isSaving {
                    ProgressView()
                } else {
                    Label("Enregistrer", systemImage: "checkmark")
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(!model.canSave)
            .accessibilityHint("Enregistre ton nom et ta photo")
        }
    }
}

/// Section « Zone sensible » : supprimer le compte, en deux confirmations.
struct AccountDeleteSection<Header: View>: View {
    let model: AccountViewModel
    /// Optionnel : absent dans les previews (« Se reconnecter » déconnecte la session).
    let session: SessionViewModel?
    @ViewBuilder var header: () -> Header
    /// Premier temps de la suppression.
    @State private var isConfirmingFirstStep = false

    var body: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingFirstStep = true
            } label: {
                HStack {
                    Label("Supprimer mon compte", systemImage: "person.crop.circle.badge.xmark")
                        .symbolRenderingMode(.hierarchical)
                    Spacer()
                    if model.isDeleting { ProgressView() }
                }
            }
            .disabled(model.isDeleting || model.user == nil)
            .accessibilityHint("Demande deux confirmations avant d'effacer ton compte")
            .grenierHaptic(.warning, trigger: isConfirmingFirstStep) { _, new in new }
            .grenierHaptic(.error, trigger: model.deletionState) { _, new in
                if case .failed = new { true } else { new == .needsReauthentication }
            }
            .grenierHaptic(.success, trigger: model.deletionState) { _, new in new == .deleted }
            .modifier(DeletionDialogs(model: model, session: session, isConfirmingFirstStep: $isConfirmingFirstStep))
        } header: {
            header()
        } footer: {
            Text("Efface ton profil, te retire de ton ménage et supprime ton compte de connexion. C'est irréversible.")
        }
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
            String(localized: "Supprimer ton compte ?"),
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
            String(localized: "Dernière confirmation"),
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
            Text("Pour protéger ton compte, LeGrenier demande une connexion récente avant de le supprimer. Reconnecte-toi, puis reviens ici.")
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

// MARK: - Previews

private func previewModel(error: AuthError? = nil) -> AccountViewModel {
    let context = AppContext.instant
    let auth = FakeAuthService(signedInUser: .sample, nextError: error, latency: .milliseconds(600))
    return AccountViewModel(repositories: context.repositories, userId: context.userId, auth: auth)
}

private struct AccountSectionsPreview: View {
    @State var model: AccountViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Compte") { AccountEditRows(model: model) }
                AccountDeleteSection(model: model, session: nil) { Text("Zone sensible") }
            }
            .navigationTitle("Profil")
        }
    }
}

#Preview("Clair") {
    AccountSectionsPreview(model: previewModel())
}

#Preview("Sombre") {
    AccountSectionsPreview(model: previewModel())
        .preferredColorScheme(.dark)
}

#Preview("Reconnexion requise") {
    AccountSectionsPreview(model: previewModel(error: .requiresRecentLogin))
}

#Preview("AX5") {
    AccountSectionsPreview(model: previewModel())
        .dynamicTypeSize(.accessibility5)
}
