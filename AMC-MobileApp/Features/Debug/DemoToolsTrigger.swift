import SwiftUI

/// Compte les taps rapprochés : 5 taps en moins de 3 s ouvrent les outils de démo.
nonisolated struct TapBurstCounter: Sendable, Equatable {
    var requiredTaps = 5
    var window: TimeInterval = 3
    private(set) var taps: [Date] = []

    /// Enregistre un tap ; true quand la rafale est complète (le compteur repart alors de zéro).
    mutating func register(at date: Date) -> Bool {
        taps = taps.filter { date.timeIntervalSince($0) <= window } + [date]
        guard taps.count >= requiredTaps else { return false }
        taps.removeAll()
        return true
    }
}

extension View {
    /// Point d'entrée caché des outils de démo : 5 taps ou appui long sur la vue.
    /// Sans effet en Release, sauf avec l'argument de lancement `-demoTools`.
    func demoToolsTrigger(isEnabled: Bool = DemoToolsGate.current) -> some View {
        modifier(DemoToolsTriggerModifier(isEnabled: isEnabled))
    }
}

private struct DemoToolsTriggerModifier: ViewModifier {
    let isEnabled: Bool
    /// Injecté par la racine de l'app ; absent dans les previews (on en crée un local).
    @Environment(DemoEnvironment.self) private var demo: DemoEnvironment?
    @State private var counter = TapBurstCounter()
    @State private var isPresented = false
    @State private var fallback = DemoEnvironment(context: .instant, mode: .fake)

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(.rect)
                .onTapGesture {
                    if counter.register(at: .now) { isPresented = true }
                }
                .onLongPressGesture(minimumDuration: 0.8) { isPresented = true }
                // VoiceOver : l'action reste découvrable dans le rotor des actions, sans gêner la lecture.
                .accessibilityAction(named: "Ouvrir les outils de démo") { isPresented = true }
                .grenierHaptic(.selection, trigger: isPresented) { _, new in new }
                .sheet(isPresented: $isPresented) {
                    DemoResetScreen(demo: demo ?? fallback)
                        .presentationDetents([.medium, .large])
                }
        } else {
            content
        }
    }
}

/// Version et build de l'app (« Version 1.0 (1) »), support du geste caché dans le Profil.
struct AppVersionLabel: View {
    var bundle: Bundle = .main

    private var version: String {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        LabeledContent {
            Text(version)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } label: {
            Label("Version de Grenier", systemImage: "info.circle")
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Version — clair") {
    Form {
        Section { AppVersionLabel().demoToolsTrigger(isEnabled: true) }
    }
}

#Preview("Version — sombre") {
    Form {
        Section { AppVersionLabel().demoToolsTrigger(isEnabled: true) }
    }
    .preferredColorScheme(.dark)
}
