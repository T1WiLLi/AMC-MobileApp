import SwiftUI

/// B-056 : carte du créateur sur la fiche du groupe. Bascule public / privé et, pour un groupe privé,
/// les invitations à usage unique : en créer une, l'envoyer (ShareLink), voir son état, la révoquer.
struct GroupPrivacyCard: View {
    @Environment(\.groupTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: GroupInvitationsViewModel
    /// Le groupe a changé de visibilité.
    var onGroupChanged: (NeighborhoodGroup) -> Void

    @State private var confirmingRevoke: GroupInvitation?
    /// Invitation dont le QR est affiché en feuille (B-058).
    @State private var showingQR: GroupInvitation?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: privateBinding) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Groupe privé")
                            .font(.headline)
                            .foregroundStyle(.texte)
                        Text(model.isPrivate
                             ? "Jamais listé. On y entre seulement avec une invitation que tu envoies."
                             : "Listé près de chez toi : tous les voisins peuvent le trouver et le rejoindre.")
                            .font(.subheadline)
                            .foregroundStyle(.texteSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: model.isPrivate ? "lock.fill" : "globe.americas.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.accent)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .tint(theme.accent)
            .disabled(model.isWorking)

            if model.isPrivate {
                Divider()
                invitations
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .grenierCard()
        .animation(reduceMotion ? nil : .smooth, value: model.isPrivate)
        .animation(reduceMotion ? nil : .smooth, value: model.items)
        .alert(
            model.actionError?.title ?? "",
            isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } }),
            presenting: model.actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .confirmationDialog(
            "Révoquer l'invitation \(confirmingRevoke?.code ?? "") ?",
            isPresented: Binding(get: { confirmingRevoke != nil }, set: { if !$0 { confirmingRevoke = nil } }),
            titleVisibility: .visible,
            presenting: confirmingRevoke
        ) { invitation in
            Button("Révoquer", role: .destructive) {
                Task { await model.revoke(invitation) }
            }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Le lien ne fera plus entrer personne. Tu pourras en créer un autre.")
        }
        .sheet(item: $showingQR) { invitation in
            InvitationQRSheet(invitation: invitation, groupName: model.group.name)
                .environment(\.groupTheme, theme)
        }
    }

    private var privateBinding: Binding<Bool> {
        Binding(
            get: { model.isPrivate },
            set: { isPrivate in
                Task {
                    guard let group = await model.setPrivate(isPrivate) else { return }
                    onGroupChanged(group)
                    if isPrivate { await model.load() }
                }
            }
        )
    }

    // MARK: Invitations

    @ViewBuilder
    private var invitations: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Invitations")
                    .font(.headline)
                    .foregroundStyle(.texte)
            } icon: {
                Image(systemName: "envelope.badge.person.crop.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent)
            }
            Text("Chaque invitation fait entrer une seule famille. Comme tu as créé le groupe, tu es la seule personne à pouvoir en créer et les annuler.")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)

            if let created = model.lastCreated, created.status == .active {
                ShareLink(
                    item: GroupInvitationsViewModel.shareMessage(groupName: model.group.name, invitation: created),
                    subject: Text("Invitation à \(model.group.name)"),
                    preview: SharePreview(String(localized: "Invitation à \(model.group.name)"), image: Image(systemName: "envelope.fill"))
                ) {
                    Label("Envoyer l'invitation \(created.code)", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .fontWeight(.semibold)
                .tint(theme.accent)

                Button {
                    showingQR = created
                } label: {
                    Label("Afficher le code QR", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .tint(theme.accent)
                .accessibilityHint("Un voisin le scanne avec l'appareil photo pour rejoindre le groupe")
            }

            Button {
                Task { await model.create() }
            } label: {
                Group {
                    if model.isWorking {
                        ProgressView()
                    } else {
                        Label("Créer une invitation", systemImage: "plus")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .fontWeight(.semibold)
            .tint(theme.accent)
            .disabled(model.isWorking)

            switch model.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .failed(let error):
                Label(error.message, systemImage: error.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            case .empty:
                Text("Aucune invitation pour l'instant.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            case .loaded(let items):
                VStack(spacing: 0) {
                    ForEach(items) { invitation in
                        InvitationRow(
                            invitation: invitation,
                            groupName: model.group.name,
                            isWorking: model.isWorking,
                            onShowQR: { showingQR = invitation },
                            onRevoke: { confirmingRevoke = invitation }
                        )
                        if invitation.id != items.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

/// Une invitation : code, état (active, utilisée, révoquée), envoyer et révoquer si elle est active.
private struct InvitationRow: View {
    @Environment(\.groupTheme) private var theme
    let invitation: GroupInvitation
    let groupName: String
    let isWorking: Bool
    let onShowQR: () -> Void
    let onRevoke: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { details; Spacer(minLength: 8); actions }
            VStack(alignment: .leading, spacing: 8) { details; actions }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(invitation.code)
                .font(.body.bold())
                .fontDesign(.monospaced)
                .tracking(2)
                .foregroundStyle(invitation.status == .active ? .texte : .texteSecondaire)
                .strikethrough(invitation.status == .revoked)
                .textSelection(.enabled)
                .accessibilityLabel(invitation.code.map(String.init).joined(separator: " "))
            Label(statusText, systemImage: statusSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusTint)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        if invitation.status == .active {
            HStack(spacing: 8) {
                ShareLink(item: GroupInvitationsViewModel.shareMessage(groupName: groupName, invitation: invitation)) {
                    Label("Envoyer", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.glass)
                .tint(theme.accent)
                .accessibilityLabel("Envoyer l'invitation \(invitation.code)")
                Button(action: onShowQR) {
                    Label("Code QR", systemImage: "qrcode")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .tint(theme.accent)
                .accessibilityLabel("Code QR de l'invitation \(invitation.code)")
                Button(role: .destructive, action: onRevoke) {
                    Label("Révoquer", systemImage: "xmark.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .disabled(isWorking)
                .accessibilityLabel("Révoquer l'invitation \(invitation.code)")
            }
        }
    }

    private var statusText: String {
        switch invitation.status {
        case .active:
            String(localized: "Active · créée \(invitation.createdAt.formatted(.relative(presentation: .named).locale(AppLanguage.formattingLocale)))")
        case .used:
            String(localized: "Utilisée \((invitation.usedAt ?? invitation.createdAt).formatted(.relative(presentation: .named).locale(AppLanguage.formattingLocale)))")
        case .revoked:
            String(localized: "Révoquée")
        }
    }

    private var statusSymbol: String {
        switch invitation.status {
        case .active: "checkmark.circle.fill"
        case .used: "person.crop.circle.badge.checkmark"
        case .revoked: "xmark.circle.fill"
        }
    }

    private var statusTint: Color {
        switch invitation.status {
        case .active: .economie
        case .used: .texteSecondaire
        case .revoked: .red
        }
    }
}

/// B-058 : QR de l'invitation à usage unique, à faire scanner à un voisin. L'appareil photo ouvre
/// `grenier://join/<code>`, et l'app présente « Rejoindre avec un code » déjà rempli.
struct InvitationQRSheet: View {
    @Environment(\.groupTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let invitation: GroupInvitation
    let groupName: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Fais scanner ce code par la famille que tu invites. Il ne sert qu'une fois.")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    QRCodeImage(Self.payload(for: invitation),
                                accessibilityLabel: String(localized: "Code QR de l'invitation à \(groupName)"))
                        .padding(12)
                        .background(Color.surface, in: .rect(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.accent.opacity(0.35), lineWidth: 1.5))
                        .frame(maxWidth: 280)

                    VStack(spacing: 2) {
                        Label("Code d'invitation", systemImage: "ticket.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.texteSecondaire)
                        Text(invitation.code)
                            .font(.title2.bold())
                            .fontDesign(.monospaced)
                            .tracking(4)
                            .foregroundStyle(.texte)
                            .textSelection(.enabled)
                            .accessibilityLabel(invitation.code.map(String.init).joined(separator: " "))
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(Color.fond)
            .navigationTitle(groupName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Ce que le QR encode : le lien que l'app ouvre, sinon le code seul.
    static func payload(for invitation: GroupInvitation) -> String {
        invitation.appURL?.absoluteString ?? invitation.code
    }
}

/// B-056 : sur la fiche d'un groupe privé, pour qui ne l'a pas créé.
struct PrivateGroupNote: View {
    @Environment(\.groupTheme) private var theme
    let isMember: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Groupe privé")
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text(isMember
                     ? "Il n'apparaît dans aucune liste. Pour inviter une famille, demande une invitation à la personne qui l'a créé."
                     : "On y entre seulement avec une invitation de la personne qui l'a créé.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "lock.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Créateur, groupe privé") {
    let data = FakeData.montreal
    let group = data.groups.first { !$0.isPublic }!
    let model = GroupInvitationsViewModel(repositories: .fake(data: data), group: group, userId: FakeData.ID.amina)
    ScrollView {
        GroupPrivacyCard(model: model, onGroupChanged: { _ in })
            .padding(16)
    }
    .grenierBackground()
    .task { await model.load() }
}
#endif
