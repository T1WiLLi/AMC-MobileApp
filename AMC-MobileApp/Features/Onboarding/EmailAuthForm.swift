import SwiftUI

/// Formulaire courriel et mot de passe sous « Continuer avec Google » : connexion ou création de compte,
/// validation en direct, erreurs sous le champ concerné, lien « Mot de passe oublié ? ».
struct EmailAuthForm: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn, signUp
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .signIn: "Se connecter"
            case .signUp: "Créer un compte"
            }
        }
    }

    private enum Field: Hashable {
        case firstName, email, password
    }

    let session: SessionViewModel

    @State private var mode: Mode = .signIn
    @State private var firstName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var attemptedSubmit = false
    @State private var showsReset = false
    /// Champs déjà quittés une fois : on n'affiche l'erreur de format qu'après.
    @State private var visited: Set<Field> = []
    @FocusState private var focus: Field?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isBusy: Bool { session.isSigningIn }
    private var emailIsValid: Bool { EmailAuthValidation.isValidEmail(email) }
    private var passwordIsLongEnough: Bool { password.count >= EmailAuthValidation.minimumPasswordLength }
    private var firstNameIsValid: Bool { !firstName.trimmingCharacters(in: .whitespaces).isEmpty }
    private var strength: PasswordStrength { PasswordStrength(password) }

    private var canSubmit: Bool {
        emailIsValid && passwordIsLongEnough && (mode == .signIn || firstNameIsValid) && !isBusy
    }

    private var serverError: AuthError? { session.emailAuthError }

    var body: some View {
        VStack(spacing: 14) {
            Picker("Mode", selection: $mode.animation(reduceMotion ? nil : .smooth)) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Se connecter ou créer un compte")

            if mode == .signUp {
                field(
                    icon: "person.fill",
                    issue: attemptedSubmit && !firstNameIsValid ? "Ton prénom, pour que ton groupe te reconnaisse." : nil,
                    isValid: firstNameIsValid
                ) {
                    TextField("Prénom", text: $firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .firstName)
                        .onSubmit { focus = .email }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            field(icon: "envelope.fill", issue: emailIssue, isValid: emailIsValid) {
                TextField("Courriel", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
            }

            VStack(alignment: .leading, spacing: 8) {
                field(icon: "lock.fill", issue: passwordIssue, isValid: mode == .signUp && passwordIsLongEnough) {
                    HStack {
                        Group {
                            if showsPassword {
                                TextField("Mot de passe", text: $password)
                            } else {
                                SecureField("Mot de passe", text: $password)
                            }
                        }
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focus, equals: .password)
                        .onSubmit(submit)

                        Button {
                            showsPassword.toggle()
                        } label: {
                            Image(systemName: showsPassword ? "eye.slash.fill" : "eye.fill")
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(Color.texteSecondaire)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showsPassword ? "Masquer le mot de passe" : "Afficher le mot de passe")
                        .sensoryFeedback(.selection, trigger: showsPassword)
                    }
                }

                if mode == .signUp, !password.isEmpty {
                    StrengthMeter(strength: strength)
                        .transition(.opacity)
                }
            }

            if let serverError, serverError.field == .general {
                Label(serverError.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                    } else {
                        Image(systemName: mode == .signUp ? "person.crop.circle.badge.plus" : "arrow.right.circle.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    Text(mode.title)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(canSubmit ? Color.onAccent : Color.texteSecondaire)
            }
            .buttonStyle(.glassProminent)
            .disabled(!canSubmit)
            .accessibilityHint(canSubmit ? "" : "Remplis les champs pour continuer")

            if mode == .signIn {
                Button {
                    showsReset = true
                } label: {
                    Label("Mot de passe oublié ?", systemImage: "key.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: serverError)
        .animation(reduceMotion ? nil : .smooth, value: mode)
        .animation(reduceMotion ? nil : .smooth, value: emailIssue)
        .animation(reduceMotion ? nil : .smooth, value: passwordIssue)
        .sensoryFeedback(.selection, trigger: mode)
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
        // En création, on compte les caractères manquants en direct ; en connexion, seulement après un essai.
        if (mode == .signUp || attemptedSubmit), let issue = EmailAuthValidation.passwordIssue(password) { return issue }
        if attemptedSubmit && password.isEmpty { return String(localized: "Entre ton mot de passe.") }
        return nil
    }

    private func submit() {
        attemptedSubmit = true
        guard canSubmit else {
            focus = !emailIsValid ? .email : (!passwordIsLongEnough ? .password : (mode == .signUp && !firstNameIsValid ? .firstName : nil))
            return
        }
        focus = nil
        Task {
            switch mode {
            case .signIn: await session.signIn(email: email, password: password)
            case .signUp: await session.signUp(email: email, password: password, displayName: firstName)
            }
        }
    }

    // MARK: Champ

    private func field<Content: View>(
        icon: String,
        issue: String?,
        isValid: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(issue == nil ? Color.grenier : .red)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                content()
                    .frame(minHeight: 44)
                if isValid && issue == nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.economie)
                        .symbolEffect(.bounce, value: isValid)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .background(Color.surface, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(issue == nil ? Color.clear : Color.red.opacity(0.7), lineWidth: 1)
            }

            if let issue {
                Label(issue, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }
}

/// Barre de force du mot de passe (création de compte).
private struct StrengthMeter: View {
    let strength: PasswordStrength

    private var color: Color {
        switch strength {
        case .tooShort: .red
        case .weak: .orange
        case .fair: .yellow
        case .strong: Color.economie
        }
    }

    private var icon: String {
        switch strength {
        case .tooShort, .weak: "shield.slash.fill"
        case .fair: "shield.lefthalf.filled"
        case .strong: "checkmark.shield.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: strength.progress)
                .tint(color)
                .animation(.smooth, value: strength)
            Label(strength.label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
                .fixedSize()
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Force du mot de passe : \(strength.label)")
        .sensoryFeedback(.impact(weight: .light), trigger: strength)
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
                Image(systemName: sent ? "checkmark.circle.fill" : "key.horizontal.fill")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(sent ? Color.economie : Color.grenier)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: sent)
                    .accessibilityHidden(true)

                Text(sent ? "Lien envoyé ! Ouvre le courriel pour choisir un nouveau mot de passe." : "Entre ton courriel : on t'envoie un lien pour choisir un nouveau mot de passe.")
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
                        Text(sent ? "OK" : "Envoyer le lien")
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
        EmailAuthForm(session: SessionViewModel(auth: FakeAuthService()))
            .padding(24)
    }
    .grenierBackground()
    .tint(.grenier)
}
