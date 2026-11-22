import SwiftUI

/// Formulaire courriel et mot de passe de la feuille de connexion (T-124) : champs à étiquette intégrée,
/// validation en direct, erreurs sous le champ concerné. À l'inscription : avatar qui prend l'initiale
/// du prénom et règles du mot de passe en liste à cocher. Le mode est piloté par `SignInScreen`.
struct EmailAuthForm: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn, signUp
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .signIn: "Se connecter"
            case .signUp: "Créer mon compte"
            }
        }
    }

    private enum Field: Hashable {
        case firstName, email, password
    }

    let session: SessionViewModel
    @Binding var mode: Mode

    @State private var firstName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showsPassword = false
    /// Largeur de l'icône de tête et côté du bouton œil : suivent Dynamic Type pour ne jamais déborder
    /// sur le libellé (à AX5, un symbole dans un cadre fixe dépassait sur « Mot de passe »).
    @ScaledMetric(relativeTo: .body) private var fieldIconWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var eyeButtonSide: CGFloat = 44
    @State private var attemptedSubmit = false
    @State private var showsReset = false
    /// Champs déjà quittés une fois : on n'affiche l'erreur de format qu'après.
    @State private var visited: Set<Field> = []
    @FocusState private var focus: Field?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isBusy: Bool { session.isSigningIn }
    private var emailIsValid: Bool { EmailAuthValidation.isValidEmail(email) }
    private var passwordIsLongEnough: Bool { password.count >= EmailAuthValidation.minimumPasswordLength }
    private var trimmedFirstName: String { firstName.trimmingCharacters(in: .whitespaces) }
    private var firstNameIsValid: Bool { !trimmedFirstName.isEmpty }

    private var canSubmit: Bool {
        emailIsValid && passwordIsLongEnough && (mode == .signIn || firstNameIsValid) && !isBusy
    }

    private var serverError: AuthError? { session.emailAuthError }

    var body: some View {
        VStack(spacing: 14) {
            if mode == .signUp {
                WelcomeAvatar(firstName: trimmedFirstName)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Champs groupés dans une seule carte, comme les réglages iOS : une ligne par champ, séparateurs fins.
            VStack(spacing: 0) {
                if mode == .signUp {
                    row(.firstName, icon: "person.fill", placeholder: "Ton prénom", text: firstName,
                        issue: firstNameIssue, isValid: firstNameIsValid) {
                        TextField("", text: $firstName)
                            .accessibilityLabel("Prénom")
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                            .focused($focus, equals: .firstName)
                            .onSubmit { focus = .email }
                    }
                    .transition(.opacity)
                    rowDivider
                }

                row(.email, icon: "envelope.fill", placeholder: "Courriel", text: email,
                    issue: emailIssue, isValid: emailIsValid) {
                    TextField("", text: $email)
                        .accessibilityLabel("Courriel")
                        .textContentType(mode == .signUp ? .emailAddress : .username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                }

                rowDivider

                row(.password, icon: showsPassword ? "lock.open.fill" : "lock.fill", placeholder: "Mot de passe",
                    text: password, issue: passwordIssue, isValid: mode == .signUp && passwordIsLongEnough) {
                    Group {
                        if showsPassword {
                            TextField("", text: $password)
                        } else {
                            SecureField("", text: $password)
                        }
                    }
                    .accessibilityLabel("Mot de passe")
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focus, equals: .password)
                    .onSubmit(submit)
                } trailing: {
                    Button {
                        showsPassword.toggle()
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash.fill" : "eye.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(Color.texteSecondaire)
                            .frame(width: eyeButtonSide, height: eyeButtonSide)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsPassword ? String(localized: "Masquer le mot de passe") : String(localized: "Afficher le mot de passe"))
                    .sensoryFeedback(.selection, trigger: showsPassword)
                }
            }
            .background(Color.surface, in: .rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: focus == nil && fieldIssues.isEmpty ? 1 : 1.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: focus)

            if !fieldIssues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(fieldIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            if mode == .signUp {
                PasswordRules(password: password)
                    .transition(.opacity)
            } else {
                Button("Mot de passe oublié ?") { showsReset = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.grenier)
                    .buttonStyle(.plain)
                    .frame(minHeight: 32)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
                    .transition(.opacity)
            }

            if let serverError, serverError.field == .general {
                Label(serverError.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.09), in: .rect(cornerRadius: 14))
                    .transition(.opacity)
            }

            // Toujours orange et actif (sauf pendant l'envoi) : un toucher sur un formulaire incomplet
            // montre les erreurs et place le curseur sur le champ à corriger, au lieu d'un bouton gris muet.
            Button(action: submit) {
                HStack(spacing: 8) {
                    Text(mode.title)
                        .font(.headline)
                        .contentTransition(.opacity)
                    if session.isSigningIn(with: .email) {
                        ProgressView()
                            .tint(Color.onAccent)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Color.onAccent)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.grenier)
            .disabled(isBusy)
            .padding(.top, 4)
        }
        .animation(reduceMotion ? nil : .smooth, value: serverError)
        .animation(reduceMotion ? nil : .smooth, value: mode)
        .animation(reduceMotion ? nil : .smooth, value: fieldIssues)
        .sensoryFeedback(.error, trigger: serverError) { _, new in new != nil }
        .onChange(of: focus) { old, _ in
            if let old { visited.insert(old) }
        }
        .onChange(of: email) { session.clearEmailError(for: .email) }
        .onChange(of: password) { session.clearEmailError(for: .password) }
        .onChange(of: mode) {
            attemptedSubmit = false
            session.clearEmailError()
        }
        .sheet(isPresented: $showsReset) {
            PasswordResetSheet(session: session, initialEmail: email)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.texteSecondaire.opacity(0.18))
            .frame(height: 1)
            .padding(.leading, 16 + fieldIconWidth + 12)
    }

    private var cardStroke: Color {
        if !fieldIssues.isEmpty { return Color.red.opacity(0.7) }
        if focus != nil { return Color.grenier.opacity(0.7) }
        return Color.texteSecondaire.opacity(0.15)
    }

    /// Erreurs des champs, dans l'ordre de la carte, affichées sous la carte.
    private var fieldIssues: [String] {
        [mode == .signUp ? firstNameIssue : nil, emailIssue, passwordIssue].compactMap { $0 }
    }

    private var firstNameIssue: String? {
        attemptedSubmit && !firstNameIsValid ? String(localized: "Ton prénom, pour que ton groupe te reconnaisse.") : nil
    }

    // MARK: Validation affichée

    private var emailIssue: String? {
        if let serverError, serverError.field == .email { return serverError.localizedDescription }
        let showFormat = attemptedSubmit || (visited.contains(.email) && focus != .email)
        if showFormat, let issue = EmailAuthValidation.emailIssue(email) { return issue }
        if attemptedSubmit && email.isEmpty { return String(localized: "Entre ton courriel.") }
        return nil
    }

    private var passwordIssue: String? {
        if let serverError, serverError.field == .password { return serverError.localizedDescription }
        // En création, la liste des règles montre déjà la longueur : l'erreur n'apparaît qu'après un essai.
        if attemptedSubmit, let issue = EmailAuthValidation.passwordIssue(password) { return issue }
        if attemptedSubmit && password.isEmpty { return String(localized: "Entre ton mot de passe.") }
        return nil
    }

    private func submit() {
        attemptedSubmit = true
        guard canSubmit else {
            focus = mode == .signUp && !firstNameIsValid ? .firstName : (!emailIsValid ? .email : (!passwordIsLongEnough ? .password : nil))
            return
        }
        focus = nil
        Task {
            switch mode {
            case .signIn: await session.signIn(email: email, password: password)
            case .signUp: await session.signUp(email: email, password: password, displayName: trimmedFirstName)
            }
        }
    }

    // MARK: Ligne de champ

    /// Ligne de la carte : icône, saisie avec indice dessiné à la main, coche de validité, accessoire.
    /// L'indice est un `Text` aux couleurs de l'app (et non le `prompt` du système) : sur appareil,
    /// le prompt d'un champ courriel pouvait sortir teinté en bleu.
    private func row<Content: View, Trailing: View>(
        _ kind: Field,
        icon: String,
        placeholder: LocalizedStringKey,
        text: String,
        issue: String?,
        isValid: Bool,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        let isFocused = focus == kind
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(issue != nil ? Color.red : (isFocused ? Color.grenier : Color.texteSecondaire))
                .frame(width: fieldIconWidth)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : isFocused)
                .symbolEffect(.wiggle, options: .nonRepeating, value: reduceMotion ? false : issue != nil)
                .accessibilityHidden(true)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Color.texteSecondaire)
                        // AX5 : « Mot de passe » passe sur autant de lignes qu'il faut au lieu d'être coupé en « Mot de… ».
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                content()
                    .foregroundStyle(Color.texte)
                    .tint(Color.grenier)
            }
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            if isValid && issue == nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.economie)
                    .symbolEffect(.bounce, value: isValid)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
            trailing()
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .contentShape(.rect)
        .onTapGesture { focus = kind }
    }
}

/// En-tête de l'inscription : avatar rond qui prend l'initiale du prénom, et salutation.
private struct WelcomeAvatar: View {
    let firstName: String

    private var initial: String { firstName.first.map { String($0).uppercased() } ?? "" }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.grenier.opacity(0.14))
                if initial.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(Color.grenier)
                } else {
                    Text(initial)
                        .font(.title.weight(.heavy))
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.grenier)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 52, height: 52)
            .overlay(Circle().strokeBorder(Color.surface, lineWidth: 3))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(firstName.isEmpty ? String(localized: "Bienvenue !") : String(localized: "Salut \(firstName) !"))
                    .font(.title3.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.texte)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                Text("Ton groupe te verra avec ce prénom.")
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.smooth, value: initial)
        .accessibilityElement(children: .combine)
    }
}

/// Règles du mot de passe en liste à cocher (création de compte, FB-02) : un cercle vide qui devient
/// une coche verte quand la règle est remplie. Seule la longueur est obligatoire ; les deux autres sont des conseils.
private struct PasswordRules: View {
    let password: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rules: [(label: String, isMet: Bool)] {
        [
            (String(localized: "Au moins \(EmailAuthValidation.minimumPasswordLength) caractères"),
             password.count >= EmailAuthValidation.minimumPasswordLength),
            (String(localized: "Un chiffre (conseillé)"), password.contains(where: \.isNumber)),
            (String(localized: "Une majuscule ou un symbole (conseillé)"),
             password.contains(where: \.isUppercase) || password.contains(where: { !$0.isLetter && !$0.isNumber }))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rules, id: \.label) { rule in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: rule.isMet ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(rule.isMet ? Color.economie : Color.texteSecondaire)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : rule.isMet)
                    Text(rule.label)
                        .foregroundStyle(rule.isMet ? Color.texte : Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote.weight(.medium))
                .animation(reduceMotion ? nil : .smooth, value: rule.isMet)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let met = rules.filter(\.isMet).map(\.label)
        return met.isEmpty
            ? String(localized: "Mot de passe : aucune règle remplie")
            : String(localized: "Mot de passe, règles remplies : \(met.formatted(.list(type: .and).locale(AppLanguage.formattingLocale)))")
    }
}

/// Feuille « Mot de passe oublié ? » : envoie le lien de réinitialisation.
private struct PasswordResetSheet: View {
    let session: SessionViewModel
    @State var email: String
    @State private var isSending = false
    @State private var sent = false
    @State private var error: AuthError?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(session: SessionViewModel, initialEmail: String) {
        self.session = session
        _email = State(initialValue: initialEmail)
    }

    private var canSend: Bool { EmailAuthValidation.isValidEmail(email) && !isSending }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Scène qui change à l'envoi : clé et cadenas, puis courriel parti avec la coche.
                GrenierSymbolScene(
                    symbol: sent ? "checkmark.circle.fill" : "key.horizontal.fill",
                    tint: sent ? .economie : .grenier,
                    satellites: sent
                        ? [.init("envelope.fill"), .init("paperplane.fill", tint: .economie)]
                        : [.init("lock.fill"), .init("envelope.fill")],
                    trigger: sent,
                    isCompact: true
                )
                .id(sent)
                .transition(.opacity)

                Text(sent ? String(localized: "Lien envoyé ! Ouvre le courriel pour choisir un nouveau mot de passe.") : String(localized: "Entre ton courriel : on t'envoie un lien pour choisir un nouveau mot de passe."))
                    .font(.body)
                    .foregroundStyle(Color.texteSecondaire)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if !sent {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(Color.grenier)
                                .accessibilityHidden(true)
                            ZStack(alignment: .leading) {
                                if email.isEmpty {
                                    Text("nom@exemple.ca")
                                        .foregroundStyle(Color.texteSecondaire)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                                TextField("", text: $email)
                                    .accessibilityLabel("Courriel")
                                    .foregroundStyle(Color.texte)
                                    .tint(Color.grenier)
                                    .focused($focused)
                            }
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.send)
                                .onSubmit(send)
                                .frame(minHeight: 44)
                        }
                        .padding(.horizontal, 14)
                        .background(Color.surface, in: .rect(cornerRadius: 16))

                        if let message = error?.localizedDescription ?? EmailAuthValidation.emailIssue(email) {
                            Label(message, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Spacer(minLength: 0)

                Button(action: sent ? { dismiss() } : send) {
                    HStack(spacing: 8) {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: sent ? "checkmark" : "paperplane.fill")
                        }
                        Text(sent ? "OK" : String(localized: "Envoyer le lien"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(canSend || sent ? Color.onAccent : Color.texteSecondaire)
                }
                .buttonStyle(.glassProminent)
                .disabled(!canSend && !sent)
            }
            .padding(24)
            .navigationTitle("Mot de passe oublié")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .animation(.smooth, value: sent)
            .sensoryFeedback(.success, trigger: sent) { _, new in new }
            .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
            .onChange(of: email) { error = nil }
            .onAppear { if email.isEmpty { focused = true } }
        }
        .tint(.grenier)
        .presentationDetents([.medium, .large])
    }

    private func send() {
        guard canSend else { return }
        isSending = true
        Task {
            error = await session.sendPasswordReset(email: email)
            isSending = false
            if error == nil { sent = true }
        }
    }
}

#Preview("Formulaire") {
    ScrollView {
        EmailAuthForm(session: SessionViewModel(auth: FakeAuthService()), mode: .constant(.signUp))
            .padding(24)
    }
    .grenierBackground()
    .tint(.grenier)
}
