// LiveActivityDemoButton.swift
// Bouton de démo de la Live Activity (DEBUG). Prêt à poser dans le Profil ou une toolbar :
// `LiveActivityDemoButton()`. Lance la démo ; un deuxième tap la termine.

import SwiftUI

struct LiveActivityDemoButton: View {
    var controller: OrderActivityController = .shared
    var stepInterval: Duration = .seconds(5)

    var body: some View {
        Button {
            Task {
                if controller.isActive {
                    await controller.end()
                } else {
                    try? await controller.startDemo(stepInterval: stepInterval)
                }
            }
        } label: {
            Label(controller.isActive ? String(localized: "Terminer l'activité en direct") : String(localized: "Démo activité en direct"),
                  systemImage: controller.isActive ? "stop.circle.fill" : "livephoto.play")
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
        .sensoryFeedback(.start, trigger: controller.isActive)
        .alert(
            controller.error?.title ?? "",
            isPresented: Binding(get: { controller.error != nil }, set: { if !$0 { controller.error = nil } }),
            presenting: controller.error
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}

/// Panneau de démo pour les previews : démarrer, étape suivante, terminer, avec l'étape courante.
struct LiveActivityDemoPanel: View {
    var controller: OrderActivityController = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Activité en direct", systemImage: "livephoto")
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
            if let attributes = controller.attributes, let state = controller.state {
                let presentation = OrderActivityPresentation(attributes, state)
                Text(presentation.title).font(.subheadline.weight(.semibold))
                Text(presentation.headline)
                    .font(.subheadline)
                    .foregroundStyle(Color.grenier)
                    .contentTransition(.numericText())
            } else {
                Label("Aucune activité en cours", systemImage: "pause.circle")
                    .symbolRenderingMode(.hierarchical)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LiveActivityDemoButton(controller: controller)
        }
        .grenierCard()
        .animation(.smooth, value: controller.state)
    }
}

#Preview("Bouton de démo") {
    LiveActivityDemoPanel()
        .padding()
        .frame(maxHeight: .infinity)
        .grenierBackground()
}

#Preview("Bouton de démo, sombre") {
    LiveActivityDemoPanel()
        .padding()
        .frame(maxHeight: .infinity)
        .grenierBackground()
        .preferredColorScheme(.dark)
}
