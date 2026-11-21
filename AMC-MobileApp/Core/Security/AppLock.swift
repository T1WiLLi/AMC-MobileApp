import SwiftUI

/// Verrou de l'app par Face ID (ou code) : activable dans le Profil, se referme quand l'app passe en arrière-plan.
@MainActor
@Observable
final class AppLock {
    static let storageKey = "appLockEnabled"

    private(set) var isLocked: Bool
    private(set) var isUnlocking = false
    private(set) var lastError: AppError?

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.storageKey)
            if !isEnabled { isLocked = false }
        }
    }

    let authenticator: any BiometricAuthenticator
    private let defaults: UserDefaults

    init(authenticator: any BiometricAuthenticator = DeviceBiometricAuthenticator(), defaults: UserDefaults = .standard) {
        self.authenticator = authenticator
        self.defaults = defaults
        let enabled = defaults.bool(forKey: Self.storageKey)
        self.isEnabled = enabled
        self.isLocked = enabled
    }

    var biometry: BiometryKind { authenticator.availability() }

    /// Active le verrou après une vérification réussie (on ne verrouille pas quelqu'un qui ne peut pas déverrouiller).
    func enable() async -> Bool {
        do {
            try await authenticator.authenticate(reason: String(localized: "Active le verrou de Grenier."))
            isEnabled = true
            lastError = nil
            return true
        } catch {
            lastError = AppError(error)
            return false
        }
    }

    func disable() {
        isEnabled = false
        lastError = nil
    }

    func unlock() async {
        guard isLocked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        do {
            try await authenticator.authenticate(reason: String(localized: "Déverrouille Grenier."))
            isLocked = false
            lastError = nil
        } catch {
            lastError = AppError(error)
        }
    }

    /// À appeler quand l'app passe en arrière-plan.
    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }
}

/// Recouvre l'app par l'écran de verrouillage tant que `AppLock` est verrouillé.
struct AppLockModifier: ViewModifier {
    let lock: AppLock
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if lock.isLocked {
                    LockScreen(lock: lock)
                        .transition(.opacity)
                }
            }
            .animation(.smooth, value: lock.isLocked)
            .environment(lock)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { lock.lockIfEnabled() }
            }
    }
}

extension View {
    func appLock(_ lock: AppLock) -> some View {
        modifier(AppLockModifier(lock: lock))
    }
}

/// Écran affiché quand l'app est verrouillée.
struct LockScreen: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "basket.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .padding(24)
                .background(Color.grenier.opacity(0.12), in: .circle)
                // Cadenas en badge : le grenier est fermé, pas vide.
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: lock.isLocked ? "lock.fill" : "lock.open.fill")
                        .font(.title3)
                        .foregroundStyle(Color.onAccent)
                        .padding(8)
                        .background(Color.grenier, in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .symbolEffect(.bounce, value: lock.isLocked)
                .foregroundStyle(Color.grenier)
                .accessibilityHidden(true)
            Text("Grenier est verrouillé")
                .font(.title2.bold())
                .foregroundStyle(.texte)
            Text("Déverrouille avec \(lock.biometry.title) pour voir tes commandes et ton code de cueillette.")
                .font(.body)
                .foregroundStyle(.texteSecondaire)
                .multilineTextAlignment(.center)
            if let error = lock.lastError {
                Label(error.message, systemImage: error.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                Task { await lock.unlock() }
            } label: {
                Group {
                    if lock.isUnlocking {
                        ProgressView()
                    } else {
                        Label("Déverrouiller avec \(lock.biometry.title)", systemImage: lock.biometry.systemImage)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(Color.onAccent)
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
            .disabled(lock.isUnlocking)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fond.ignoresSafeArea())
        .task { await lock.unlock() }
    }
}

#Preview("Verrouillé") {
    let defaults = UserDefaults(suiteName: "preview-lock")!
    defaults.set(true, forKey: AppLock.storageKey)
    return LockScreen(lock: AppLock(authenticator: FakeBiometricAuthenticator(result: .failure(.invalidInput("Déverrouillage annulé."))), defaults: defaults))
}

#Preview("Verrouillé sombre") {
    let defaults = UserDefaults(suiteName: "preview-lock-dark")!
    defaults.set(true, forKey: AppLock.storageKey)
    return LockScreen(lock: AppLock(authenticator: FakeBiometricAuthenticator(), defaults: defaults))
        .preferredColorScheme(.dark)
}
