// NotificationPermissionView.swift
// Carte qui demande les notifications EN CONTEXTE (après une première part, sur l'écran de cueillette…),
// jamais au lancement. Refusé : on explique et on renvoie vers Réglages.

import SwiftUI
import UIKit

/// Carte d'autorisation des notifications.
///
///     NotificationPermissionView(scheduler: scheduler) {
///         showNotificationCard = false   // « Plus tard » ou autorisé
///     }
///
/// Ne s'affiche pas (vue vide) si les notifications sont déjà autorisées.
struct NotificationPermissionView: View {
    let scheduler: any NotificationScheduler
    /// Appelé après « Plus tard » ou une fois l'autorisation accordée : l'écran peut retirer la carte.
    var onFinish: (NotificationAuthorizationStatus) -> Void = { _ in }

    @State private var status: NotificationAuthorizationStatus?
    @State private var isRequesting = false
    @State private var error: AppError?

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 44

    var body: some View {
        Group {
            switch status {
            case .notDetermined:
                card(
                    symbol: "bell.badge.fill",
                    title: "Sache quand ton prix baisse",
                    message: "On te prévient quand un palier est débloqué, quand ta commande est prête et 1 h avant ta cueillette. Rien d'autre."
                ) {
                    enableButton
                    laterButton
                }
            case .denied:
                card(
                    symbol: "bell.slash.fill",
                    title: "Les notifications sont coupées",
                    message: "Active-les dans Réglages pour savoir quand ton prix baisse et quand passer chercher ta commande."
                ) {
                    settingsButton
                    laterButton
                }
            case .authorized, nil:
                EmptyView()
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: status)
        .sensoryFeedback(.success, trigger: status) { _, new in new == .authorized }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Retour de Réglages : l'utilisateur a peut-être rallumé les notifications.
            if phase == .active { Task { await refresh() } }
        }
    }

    // MARK: Carte

    private func card<Buttons: View>(
        symbol: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .symbolEffect(.bounce, options: .nonRepeating, isActive: !reduceMotion)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.grenier.opacity(0.12), in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error {
                Label(error.message, systemImage: error.systemImage)
                    .font(.footnote)
                    .foregroundStyle(Color.texteSecondaire)
            }

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout { buttons() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .contain)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: Boutons

    private var enableButton: some View {
        Button {
            Task { await enable() }
        } label: {
            if isRequesting {
                ProgressView()
                    .accessibilityLabel("Activation en cours")
            } else {
                Label("Activer", systemImage: "bell.fill")
            }
        }
        .buttonStyle(.glass)
        .tint(Color.grenier)
        .disabled(isRequesting)
        .accessibilityHint("Affiche la demande d'autorisation d'iOS.")
    }

    private var settingsButton: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            Label("Ouvrir Réglages", systemImage: "gear")
        }
        .buttonStyle(.glass)
        .tint(Color.grenier)
        .accessibilityHint("Ouvre les réglages de Grenier pour activer les notifications.")
    }

    private var laterButton: some View {
        Button("Plus tard") {
            onFinish(status ?? .notDetermined)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.texteSecondaire)
        .frame(minHeight: 44)
    }

    // MARK: Actions

    private func refresh() async {
        status = await scheduler.authorizationStatus()
    }

    private func enable() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            status = try await scheduler.requestAuthorization()
            error = nil
            onFinish(.authorized)
        } catch {
            // Refus : la carte « coupées » explique déjà quoi faire. Autre erreur : on l'affiche.
            let appError = AppError(error)
            self.error = appError == .notificationsDenied ? nil : appError
            status = await scheduler.authorizationStatus()
        }
    }
}

// MARK: - Previews

private struct NotificationPermissionPreview: View {
    let status: NotificationAuthorizationStatus

    var body: some View {
        ScrollView {
            NotificationPermissionView(scheduler: FakeNotificationScheduler(status: status))
                .padding()
        }
        .grenierBackground()
    }
}

#Preview("À demander") {
    NotificationPermissionPreview(status: .notDetermined)
}

#Preview("À demander, sombre") {
    NotificationPermissionPreview(status: .notDetermined)
        .preferredColorScheme(.dark)
}

#Preview("Refusé") {
    NotificationPermissionPreview(status: .denied)
}

#Preview("Refusé, sombre") {
    NotificationPermissionPreview(status: .denied)
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    NotificationPermissionPreview(status: .notDetermined)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Refusé AX5") {
    NotificationPermissionPreview(status: .denied)
        .dynamicTypeSize(.accessibility5)
}
