import SwiftUI

/// Formulaire courriel et mot de passe de la feuille de connexion (T-124) : champs à étiquette intégrée,
/// validation en direct, erreurs sous le champ concerné. À l'inscription : avatar qui prend l'initiale
/// du prénom et règles du mot de passe en pastilles. Le mode est piloté par `SignInScreen`.
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
        VStack(spacing: 10) {
            if mode == .signUp {
                WelcomeAvatar(firstName: trimmedFirstName)
                    .transition(.move(edge: .top).combined(with: .opacity))

                field(
                    .firstName,
                    label: "Prénom",
                    icon: "person.fill",
                    issue: attemptedSubmit && !firstNameIsValid ? String(localized: "Ton prénom, pour que ton groupe te reconnaisse.") : nil,
                    isValid: firstNameIsValid
                ) {
                    TextField("Prénom", text: $firstName, prompt: Text("Amina"))
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .firstName)
                        .onSubmit { focus = .email }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            field(.email, label: "Courriel", icon: "envelope.fill", issue: emailIssue, isValid: emailIsValid) {
                TextField("Courriel", text: $email, prompt: Text("nom@exemple.ca"))
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
            }

            VStack(alignment: .leading, spacing: 8) {
                field(
                    .password,
                    label: "Mot de passe",
                    icon: showsPassword ? "lock.open.fill" : "lock.fill",
                    issue: passwordIssue,
                    isValid: mode == .signUp && passwordIsLongEnough
                ) {
                    Group {
                        if showsPassword {
                            TextField("Mot de passe", text: $password, prompt: Text("Ton mot de passe"))
                        } else {
                            SecureField("Mot de passe", text: $password, prompt: Text("Ton mot de passe"))
                        }
                    }
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
                        .transition(.opacity)
                }
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

            Button(action: submit) {
                HStack(spacing: 8) {
                    Text(mode.title)
                        .font(.headline)
                        .contentTransition(.opacity)
                    if isBusy {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(canSubmit ? Color.onAccent : Color.texteSecondaire)
            }
            .buttonStyle(.glassProminent)
            .disabled(!canSubmit)
            .accessibilityHint(canSubmit ? "" : String(localized: "Remplis les champs pour continuer"))
        }
        .animation(reduceMotion ? nil : .smooth, value: serverError)
        .animation(reduceMotion ? nil : .smooth, value: mode)
        .animation(reduceMotion ? nil : .smooth, value: emailIssue)
        .animation(reduceMotion ? nil : .smooth, value: passwordIssue)
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
        // En création, les pastilles montrent déjà la longueur : l'erreur n'apparaît qu'après un essai.
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

    // MARK: Champ

    /// Champ à étiquette intégrée : icône, petit libellé au-dessus de la saisie, bordure qui suit le focus et l'erreur.
    private func field<Content: View, Trailing: View>(
        _ kind: Field,
        label: LocalizedStringKey,
        icon: String,
        issue: String?,
        isValid: Bool,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        let isFocused = focus == kind
        let accent: Color = issue != nil ? .red : (isFocused ? Color.grenier : Color.texteSecondaire)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(issue == nil ? Color.grenier : .red)
                    .frame(width: fieldIconWidth)
                    // Rebond à la prise du focus, frétillement quand une erreur apparaît.
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : isFocused)
                    .symbolEffect(.wiggle, options: .nonRepeating, value: reduceMotion ? false : issue != nil)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                    content()
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.texte)
                }
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
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .frame(minHeight: 54)
            .background(isFocused || issue != nil ? Color.surface : Color.fond, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        issue != nil ? Color.red.opacity(0.8) : (isFocused ? Color.grenier : Color.texteSecondaire.opacity(0.2)),
                        lineWidth: 1.5
                    )
            }
            .background {
                if isFocused || issue != nil {
                    RoundedRectangle(cornerRadius: 18)
                        .fill((issue != nil ? Color.red : Color.grenier).opacity(0.12))
                        .padding(-4)
                }
            }
            .contentShape(.rect(cornerRadius: 16))
            .onTapGesture { focus = kind }
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isFocused)

            if let issue {
                Label(issue, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.leading, 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
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

/// Règles du mot de passe en pastilles qui passent au vert (création de compte).
/// Seule la longueur est obligatoire ; chiffre et majuscule ou symbole sont des conseils.
private struct PasswordRules: View {
    let password: String

    private var rules: [(label: String, isMet: Bool)] {
        [
            (String(localized: "\(EmailAuthValidation.minimumPasswordLength) caractères"),
             password.count >= EmailAuthValidation.minimumPasswordLength),
            (String(localized: "Un chiffre"), password.contains(where: \.isNumber)),
            (String(localized: "Majuscule ou symbole"),
             password.contains(where: \.isUppercase) || password.contains(where: { !$0.isLetter && !$0.isNumber }))
        ]
    }

    var body: some View {
        // Sur une ligne si elles tiennent, sinon empilées (Dynamic Type).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips(rules) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { chips(Array(rules.prefix(2))) }
                chips(Array(rules.suffix(1)))
            }
            VStack(alignment: .leading, spacing: 6) { chips(rules) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private func chips(_ rules: [(label: String, isMet: Bool)]) -> some View {
        ForEach(rules, id: \.label) { rule in
            Label(rule.label, systemImage: rule.isMet ? "checkmark" : "minus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(rule.isMet ? Color.economie : Color.texteSecondaire)
                .contentTransition(.symbolEffect(.replace))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((rule.isMet ? Color.economie : Color.texteSecondaire).opacity(0.12), in: .capsule)
                .fixedSize()
                .animation(.smooth, value: rule.isMet)
        }
    }

    private var accessibilitySummary: String {
        let met = rules.filter(\.isMet).map(\.label)
        return met.isEmpty
            ? String(localized: "Mot de passe : aucune règle remplie")
            : String(localized: "Mot de passe, règles remplies : \(met.formatted(.list(type: .and)))")
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
                            TextField("Courriel", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.send)
                                .focused($focused)
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
