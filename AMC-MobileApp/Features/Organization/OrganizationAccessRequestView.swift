// OrganizationAccessRequestView.swift
// FB-16 : le portail Organismes est le seul réservé. Un compte sans organisme rattaché ne voit pas un écran vide :
// on explique comment l'obtenir et on propose « Faire une demande » (courriel prérempli) ou le retour aux Familles.
// L'équipe LeGrenier vérifie l'organisme puis relie le compte (`users/{uid}.organizationId`).

import SwiftUI

struct OrganizationAccessRequestView: View {
    /// Retour au portail Familles (bascule animée gérée par l'appelant).
    let onBackToFamily: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var requestCount = 0

    /// Courriel de demande prérempli ; le destinataire est choisi dans l'app Mail.
    static let requestURL: URL? = {
        var components = URLComponents()
        components.scheme = "mailto"
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(localized: "Rattacher mon organisme à LeGrenier")),
            URLQueryItem(
                name: "body",
                value: String(localized: "Bonjour,\n\nNotre organisme souhaite soutenir les groupes de quartier sur LeGrenier.\n\nNom de l'organisme :\nType (banque alimentaire, centre communautaire, fondation…) :\nQuartiers soutenus :\nPersonne-ressource et téléphone :\n\nMerci !")
            ),
        ]
        return components.url
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ZStack(alignment: .bottomTrailing) {
                        StateIllustration(systemImage: Portal.organization.systemImage)
                            .symbolEffect(.bounce, value: appeared && !reduceMotion)
                        Image(systemName: "lock.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.grenier)
                            .background(Color.fond, in: .circle)
                            .accessibilityHidden(true)
                    }

                    VStack(spacing: 8) {
                        Text("Portail réservé aux organismes")
                            .font(.title2.bold())
                            .foregroundStyle(.texte)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("Ton compte n'est pas encore rattaché à un organisme. Fais une demande : l'équipe LeGrenier vérifie chaque organisme avant d'ouvrir son portail.")
                            .font(.body)
                            .foregroundStyle(.texteSecondaire)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        step("envelope.fill", "Fais une demande", "Nom de l'organisme, mission et quartiers soutenus.")
                        step("checkmark.seal.fill", "On vérifie et on te contacte", "En général sous quelques jours ouvrables.")
                        step("heart.circle.fill", "Soutiens les quartiers", "Finance des paniers suspendus et parraine des groupes.")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .grenierCard(padding: 0)

                    VStack(spacing: 12) {
                        Button {
                            requestCount += 1
                            if let url = Self.requestURL { openURL(url) }
                        } label: {
                            Label("Faire une demande", systemImage: "paperplane.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.grenier)
                        .controlSize(.large)
                        .accessibilityHint("Ouvre un courriel prérempli pour nous contacter.")

                        Button(action: onBackToFamily) {
                            Label("Revenir au portail Familles", systemImage: "arrow.uturn.backward.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                        .tint(.grenier)
                        .controlSize(.large)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .grenierBackground()
            .navigationTitle(Portal.organization.title)
            .navigationBarTitleDisplayMode(.inline)
            .profileToolbar()
            .onAppear { appeared = true }
            .sensoryFeedback(.impact, trigger: requestCount)
        }
    }

    private func step(_ systemImage: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Clair") {
    OrganizationAccessRequestView {}
}

#Preview("Sombre") {
    OrganizationAccessRequestView {}
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    OrganizationAccessRequestView {}
        .dynamicTypeSize(.accessibility5)
}
