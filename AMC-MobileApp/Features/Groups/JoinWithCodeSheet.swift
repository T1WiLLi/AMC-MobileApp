// JoinWithCodeSheet.swift
// B-056 : rejoindre un groupe avec un code ou un lien d'invitation.
// Refonte (retour samuel) : fond crème opaque comme les autres feuilles, en-tête illustré, six cases
// pour le code, bouton « Coller » sans invite du système, une seule action principale en bas.

import SwiftUI

struct JoinWithCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: JoinWithCodeViewModel
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .title) private var boxHeight: CGFloat = 60
    let onJoined: (NeighborhoodGroup) -> Void

    init(repositories: AppRepositories, householdId: String, code: String = "",
         onJoined: @escaping (NeighborhoodGroup) -> Void) {
        _model = State(initialValue: JoinWithCodeViewModel(repositories: repositories, householdId: householdId, input: code))
        self.onJoined = onJoined
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    codeCard
                    notesCard
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .grenierBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) { joinBar }
            .navigationTitle("Rejoindre avec un code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
            }
            .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
            .sensoryFeedback(.success, trigger: model.joinedGroup) { _, new in new != nil }
            .onChange(of: model.joinedGroup) { _, group in
                guard let group else { return }
                onJoined(group)
                dismiss()
            }
            .onAppear { if model.input.isEmpty { isFocused = true } }
        }
        .presentationDetents([.large])
    }

    // MARK: En-tête

    private var hero: some View {
        VStack(spacing: 12) {
            // Aux tailles d'accessibilité, les cases du code remontent : pas de pastille.
            if !dynamicTypeSize.isAccessibilitySize {
                GrenierIconTile(systemImage: "ticket.fill", side: 72, shape: .circle, font: .system(size: 30, weight: .semibold))
                    .symbolEffect(.bounce, value: reduceMotion ? nil : model.code)
                    .accessibilityHidden(true)
            }
            Text("Rejoins un groupe")
                .font(.title2.bold())
                .fontDesign(.rounded)
                .foregroundStyle(Color.texte)
                .accessibilityAddTraits(.isHeader)
            Text("Tape le code de \(GroupRules.inviteCodeLength) caractères qu'on t'a envoyé, ou colle le lien d'invitation.")
                .font(.subheadline)
                .foregroundStyle(Color.texteSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        // Plafonné pour que les cases du code restent près du haut aux très grandes tailles.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    // MARK: Code

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("Code d'invitation")
                    .font(.headline)
                    .foregroundStyle(Color.texte)
            } icon: {
                Image(systemName: "number")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            .accessibilityAddTraits(.isHeader)

            codeBoxes
            statusLine
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.displayedCode)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.errorMessage)
    }

    /// Six cases qui montrent le code ; le vrai champ, transparent, est dessous et reçoit le clavier.
    private var codeBoxes: some View {
        HStack(spacing: 8) {
            ForEach(0..<GroupRules.inviteCodeLength, id: \.self) { index in
                codeBox(at: index)
            }
        }
        // Au-delà d'AX3, les cases ne tiendraient plus sur une ligne.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .background {
            // Pas de texte indicatif : il déborderait entre les cases.
            TextField(text: inputBinding, prompt: Text(verbatim: "")) {
                Text("Code ou lien d'invitation")
            }
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.join)
                .focused($isFocused)
                .onSubmit { join() }
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel("Code d'invitation")
                .accessibilityValue(spokenCode)
                .accessibilityHint("\(GroupRules.inviteCodeLength) lettres ou chiffres, ou un lien d'invitation.")
        }
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
    }

    private func codeBox(at index: Int) -> some View {
        let character = index < shownCharacters.count ? String(shownCharacters[index]) : ""
        let isActive = isFocused && index == min(shownCharacters.count, GroupRules.inviteCodeLength - 1)
            && shownCharacters.count < GroupRules.inviteCodeLength
        return ZStack {
            if character.isEmpty {
                if isActive { caret }
            } else {
                Text(character)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.texte)
                    .minimumScaleFactor(0.5)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, minHeight: boxHeight)
        .background(character.isEmpty ? Color.fond : Color.grenier.opacity(0.08), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(boxBorder(isActive: isActive, isFilled: !character.isEmpty),
                              lineWidth: isActive || model.errorMessage != nil ? 2 : 1)
        }
        .accessibilityHidden(true)
    }

    private var caret: some View {
        Capsule()
            .fill(Color.grenier)
            .frame(width: 2.5, height: boxHeight * 0.45)
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.15]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.55) }
    }

    private func boxBorder(isActive: Bool, isFilled: Bool) -> Color {
        if model.errorMessage != nil || model.isUnrecognizedLink { return .red.opacity(0.7) }
        if isActive { return .grenier }
        return isFilled ? Color.grenier.opacity(0.45) : Color.piste
    }

    /// Ce que les cases affichent : le code tapé, rien si la saisie est un lien qu'on ne lit pas.
    private var shownCharacters: [Character] {
        Array(model.displayedCode)
    }

    private var spokenCode: String {
        if model.isUnrecognizedLink { return model.input }
        if model.displayedCode.isEmpty { return String(localized: "Vide") }
        return model.displayedCode.map(String.init).joined(separator: " ")
    }

    private var inputBinding: Binding<String> {
        Binding(get: { model.input }, set: { model.updateInput($0) })
    }

    /// Une seule ligne sous les cases : l'erreur d'abord, puis ce qu'on a compris de la saisie.
    @ViewBuilder
    private var statusLine: some View {
        Group {
            if let message = model.errorMessage {
                status(message, systemImage: "exclamationmark.triangle.fill", color: .red)
            } else if model.isUnrecognizedLink {
                status(String(localized: "Ce lien n'est pas une invitation LeGrenier. Tape plutôt le code de \(GroupRules.inviteCodeLength) caractères."),
                       systemImage: "link.badge.plus", color: .red)
            } else if model.recognizedLink, model.code != nil {
                status(String(localized: "Lien d'invitation reconnu"), systemImage: "checkmark.circle.fill", color: .economie)
            } else if model.code != nil {
                status(String(localized: "Code complet, tu peux rejoindre le groupe."), systemImage: "checkmark.circle.fill", color: .economie)
            } else {
                status(String(localized: "Lettres et chiffres seulement, sans espaces."), systemImage: "info.circle.fill",
                       color: .texteSecondaire)
            }
        }
        .transition(.opacity)
    }

    private func status(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .symbolRenderingMode(.hierarchical)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(text)
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                pasteButton
                Spacer(minLength: 0)
                clearButton
            }
            VStack(alignment: .leading, spacing: 10) {
                pasteButton
                clearButton
            }
        }
    }

    /// `PasteButton` : la personne touche elle-même le bouton, donc pas d'alerte « Autoriser à coller ».
    private var pasteButton: some View {
        PasteButton(payloadType: String.self) { strings in
            guard let text = strings.first else { return }
            Task { @MainActor in
                model.updateInput(text)
                isFocused = false
            }
        }
        .buttonBorderShape(.capsule)
        .tint(.grenier)
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private var clearButton: some View {
        if !model.input.isEmpty {
            Button("Effacer", systemImage: "xmark.circle.fill") {
                model.updateInput("")
                isFocused = true
            }
            .buttonStyle(.glass)
            .foregroundStyle(Color.texteSecondaire)
            .transition(.opacity)
        }
    }

    // MARK: Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            note(title: "Où trouver le code ?",
                 detail: "Dans le message, le courriel ou le code QR envoyé par la personne qui t'invite.",
                 systemImage: "qrcode")
            Divider()
            note(title: "Usage unique",
                 detail: "Une invitation à un groupe privé sert une seule fois. Si elle a déjà servi, demandes-en une nouvelle.",
                 systemImage: "lock.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }

    private func note(title: LocalizedStringKey, detail: LocalizedStringKey, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                GrenierIconTile(systemImage: systemImage, side: 36, shape: .rounded(10), font: .body)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.texte)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Action principale

    private var joinBar: some View {
        Button(action: join) {
            HStack(spacing: 8) {
                if model.isJoining {
                    ProgressView().tint(Color.onAccent)
                } else {
                    Image(systemName: "person.badge.plus")
                }
                Text(model.isJoining ? LocalizedStringKey("Connexion au groupe…") : LocalizedStringKey("Rejoindre"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.headline)
            // Le bouton reste sur une ligne : au-delà d'AX2, il cacherait le formulaire.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .disabled(!model.canJoin)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        // Fondu crème derrière le bouton : le contenu qui défile dessous ne brouille pas son libellé.
        .background {
            LinearGradient(stops: [.init(color: Color.fond.opacity(0), location: 0),
                                   .init(color: Color.fond.opacity(0.92), location: 0.35),
                                   .init(color: Color.fond, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private func join() {
        Task { await model.join() }
    }
}

#if DEBUG
#Preview("Rejoindre avec un code") {
    Text("Groupes")
        .sheet(isPresented: .constant(true)) {
            JoinWithCodeSheet(repositories: .fake(data: .montreal), householdId: FakeData.ID.aminaHousehold, onJoined: { _ in })
        }
}

#Preview("Code prérempli, sombre") {
    Text("Groupes")
        .sheet(isPresented: .constant(true)) {
            JoinWithCodeSheet(repositories: .fake(data: .montreal), householdId: FakeData.ID.aminaHousehold,
                              code: "VIL4K7", onJoined: { _ in })
        }
        .preferredColorScheme(.dark)
}
#endif
