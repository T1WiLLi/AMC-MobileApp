import PhotosUI
import SwiftUI

/// En-tête de la fiche d'un groupe (T-122) : bannière pleine largeur qui s'étire quand on tire vers le bas
/// (parallaxe en remontant, coupée sous Reduce Motion), fondu vers le fond de page, et photo du groupe
/// en médaillon qui chevauche le bas de la bannière. Le coordinateur voit « Modifier » (photo, bannière).
struct GroupHeroHeader: View {
    let group: NeighborhoodGroup
    /// Le coordinateur peut changer les images ; nil pour les autres membres.
    let editor: GroupImageEditorViewModel?
    /// Le groupe a changé (image posée ou retirée).
    let onGroupChanged: (NeighborhoodGroup) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scaledPhotoSize: CGFloat = 96
    @State private var pickerKind: GroupImageKind = .photo
    @State private var isPickerPresented = false
    @State private var pickedItem: PhotosPickerItem?

    static let bannerHeight: CGFloat = 240
    private var photoSize: CGFloat { min(scaledPhotoSize, 140) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
            HStack(alignment: .bottom, spacing: 12) {
                groupPhoto
                Spacer(minLength: 0)
                if editor != nil { editMenu }
            }
            .padding(.horizontal, 16)
            .padding(.top, -photoSize / 2)
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $pickedItem, matching: .images, photoLibrary: .shared())
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            let kind = pickerKind
            Task {
                defer { pickedItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                await editor?.pick(data, kind: kind)
            }
        }
        .sheet(isPresented: Binding(
            get: { editor?.isPresentingPreview ?? false },
            set: { if !$0 { editor?.dismiss() } }
        )) {
            if let editor {
                GroupImageEditSheet(group: group, editor: editor, onGroupChanged: onGroupChanged) {
                    pickerKind = $0
                    isPickerPresented = true
                }
            }
        }
        .grenierHaptic(.success, trigger: editor?.successCount ?? 0) { old, new in new > old }
    }

    // MARK: Bannière

    private var banner: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
            let stretch = max(minY, 0)
            // En remontant, l'image glisse moins vite que le contenu.
            let parallax = reduceMotion ? 0 : max(-minY, 0) * 0.4
            GroupBannerImage(group: group)
                .offset(y: parallax)
                .frame(width: proxy.size.width, height: Self.bannerHeight + stretch)
                .overlay(alignment: .top) {
                    // Lisibilité des boutons de la barre de navigation.
                    LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color.fond], startPoint: .top, endPoint: .bottom)
                        .frame(height: 72)
                }
                .overlay {
                    if editor?.activeKind == .banner, editor?.status == .uploading {
                        ProgressView().controlSize(.large).tint(.white)
                    }
                }
                .clipped()
                .offset(y: -stretch)
        }
        .frame(height: Self.bannerHeight)
        .accessibilityElement()
        .accessibilityLabel(group.bannerURL == nil ? "Bannière aux couleurs de Grenier" : "Bannière du groupe \(group.name)")
        .accessibilityAddTraits(.isImage)
    }

    // MARK: Photo du groupe

    private var groupPhoto: some View {
        GroupAvatarView(group: group, size: photoSize, showsRing: true)
            .overlay {
                if editor?.activeKind == .photo, editor?.status == .uploading {
                    Circle().fill(.ultraThinMaterial).overlay { ProgressView() }
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : (editor?.successCount ?? 0)) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.08, duration: 0.18)
                SpringKeyframe(1.0, duration: 0.3)
            }
    }

    // MARK: Modifier (coordinateur)

    private var editMenu: some View {
        Menu {
            Section("Photo du groupe") {
                Button("Modifier la photo", systemImage: "person.crop.circle.badge.plus") { choose(.photo) }
                if group.photoURL != nil {
                    Button("Retirer la photo", systemImage: "trash", role: .destructive) { remove(.photo) }
                }
            }
            Section("Bannière") {
                Button("Modifier la bannière", systemImage: "photo.badge.plus") { choose(.banner) }
                if group.bannerURL != nil {
                    Button("Retirer la bannière", systemImage: "trash", role: .destructive) { remove(.banner) }
                }
            }
        } label: {
            Label("Modifier", systemImage: "camera.fill")
                .fontWeight(.semibold)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.glass)
        .tint(.grenier)
        .disabled(editor?.isBusy ?? true)
        .padding(.bottom, 4)
        .accessibilityHint("Change la photo ou la bannière du groupe. Réservé aux coordinateurs.")
    }

    private func choose(_ kind: GroupImageKind) {
        pickerKind = kind
        isPickerPresented = true
    }

    private func remove(_ kind: GroupImageKind) {
        guard let editor else { return }
        Task {
            if let group = await editor.remove(kind) {
                withAnimation(reduceMotion ? nil : .grenierSmooth) { onGroupChanged(group) }
            }
        }
    }
}

// MARK: - Bannière seule

/// Bannière du groupe, ou un dégradé maillé aux couleurs de Grenier s'il n'en a pas.
struct GroupBannerImage: View {
    let group: NeighborhoodGroup

    var body: some View {
        MediaImage(url: group.bannerURL) { GroupBannerFallback() }
    }
}

/// Dégradé maillé Grenier / Économie / Solidarité, avec le symbole des groupes en filigrane.
struct GroupBannerFallback: View {
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                .grenier, .grenier.opacity(0.85), .economie,
                .solidarite.opacity(0.8), .grenier, .economie.opacity(0.85),
                .grenier.opacity(0.9), .solidarite, .grenier,
            ]
        )
        .overlay(alignment: .trailing) {
            Image(systemName: GrenierSymbol.groups)
                .font(.system(size: 120))
                .foregroundStyle(.white.opacity(0.14))
                .rotationEffect(.degrees(-12))
                .offset(x: 24, y: 8)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Aperçu avant envoi

/// Aperçu recadré de la nouvelle photo ou bannière, puis envoi avec progression, succès ou erreur.
struct GroupImageEditSheet: View {
    let group: NeighborhoodGroup
    let editor: GroupImageEditorViewModel
    let onGroupChanged: (NeighborhoodGroup) -> Void
    /// « Choisir une autre » : rouvre Photos pour le même type d'image.
    let chooseAnother: (GroupImageKind) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kind: GroupImageKind { editor.activeKind ?? .photo }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    preview
                    statusRow
                    actions
                }
                .padding(16)
            }
            .navigationTitle(kind == .banner ? "Nouvelle bannière" : "Nouvelle photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark", role: .cancel) { editor.dismiss() }
                        .disabled(editor.status == .uploading)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(editor.status == .uploading)
        .grenierHaptic(.error, trigger: editor.error) { _, new in new != nil }
        .task(id: editor.status) {
            // Succès : on laisse voir le sceau, puis la feuille se ferme toute seule.
            guard editor.status == .succeeded else { return }
            try? await Task.sleep(for: .milliseconds(900))
            editor.dismiss()
        }
    }

    // MARK: Aperçu

    @ViewBuilder
    private var preview: some View {
        let image = editor.previewImage
        switch kind {
        case .banner:
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        GroupBannerFallback().redacted(reason: .placeholder)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(ImageSpec.banner.aspectRatio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 20))
                GroupAvatarView(group: group, size: 56, showsRing: true)
                    .padding(12)
            }
            .overlay { if editor.status == .preparing { ProgressView().controlSize(.large) } }
            .accessibilityElement()
            .accessibilityLabel("Aperçu de la nouvelle bannière, recadrée au format 8 sur 3")
        case .photo:
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.piste
                }
            }
            .frame(width: 180, height: 180)
            .clipShape(.circle)
            .overlay(Circle().stroke(Color.surface, lineWidth: 6))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .overlay { if editor.status == .preparing { ProgressView().controlSize(.large) } }
            .accessibilityElement()
            .accessibilityLabel("Aperçu de la nouvelle photo du groupe, recadrée en cercle")
        }
    }

    // MARK: État

    @ViewBuilder
    private var statusRow: some View {
        switch editor.status {
        case .idle, .ready:
            Label(kind == .banner ? "Recadrée au centre, 1200 × 450." : "Recadrée au centre, 400 × 400.",
                  systemImage: "crop")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .symbolRenderingMode(.hierarchical)
        case .preparing, .uploading:
            VStack(alignment: .leading, spacing: 8) {
                Label(editor.status == .preparing ? "Préparation de l'image…" : "Envoi aux voisins…",
                      systemImage: "arrow.up.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.grenier)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                ProgressView(value: editor.progress)
                    .tint(.grenier)
                    .animation(reduceMotion ? nil : .grenierSmooth, value: editor.progress)
            }
            .accessibilityElement(children: .combine)
        case .succeeded:
            Label(kind == .banner ? "Bannière enregistrée" : "Photo enregistrée", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color.economie)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : editor.successCount)
                .transition(.scale.combined(with: .opacity))
        case .failed(let error):
            VStack(spacing: 8) {
                Label(error.title, systemImage: error.systemImage)
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(error.message)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if case .failed = editor.status {
                Button {
                    Task { await send(retry: true) }
                } label: {
                    Label("Réessayer", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.grenier)
                .controlSize(.large)
            } else {
                Button {
                    Task { await send(retry: false) }
                } label: {
                    Label(kind == .banner ? "Utiliser cette bannière" : "Utiliser cette photo", systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.grenier)
                .controlSize(.large)
                .disabled(editor.status != .ready)
            }
            Button {
                let kind = kind
                editor.dismiss()
                chooseAnother(kind)
            } label: {
                Label("Choisir une autre", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(editor.isBusy || editor.status == .succeeded)
        }
    }

    private func send(retry: Bool) async {
        let group = retry ? await editor.retry() : await editor.confirm()
        if let group {
            withAnimation(reduceMotion ? nil : .grenierSmooth) { onGroupChanged(group) }
        }
    }
}

#if DEBUG
#Preview("En-tête — coordinateur") {
    ScrollView {
        GroupHeroHeader(
            group: CardPreviewData.group,
            editor: GroupImageEditorViewModel(repositories: .fake(behavior: .instant), groupId: CardPreviewData.group.id, userId: "amina"),
            onGroupChanged: { _ in }
        )
    }
    .ignoresSafeArea(edges: .top)
    .grenierBackground()
    .environment(\.appContext, .instant)
}

#Preview("En-tête — sans images, sombre") {
    var group = CardPreviewData.group
    group.photoURL = nil
    group.bannerURL = nil
    return ScrollView {
        GroupHeroHeader(group: group, editor: nil, onGroupChanged: { _ in })
    }
    .ignoresSafeArea(edges: .top)
    .grenierBackground()
    .environment(\.appContext, .instant)
    .preferredColorScheme(.dark)
}
#endif
