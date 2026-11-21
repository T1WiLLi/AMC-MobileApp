// VendorProfileMissingView.swift
// T-129 : le compte connecté n'a pas encore de profil producteur (`appContext.vendorId` vide).
// Plutôt qu'un tableau de bord rempli d'un faux vendeur, on explique la suite et on propose l'action utile.
//
// firestore.rules interdit la création d'un document `vendors/{id}` depuis l'app (`allow create: if false`) :
// chaque producteur est vérifié par l'équipe Grenier, qui relie ensuite le profil au compte (`users/{uid}.vendorId`).
// L'action principale ouvre donc une demande par courriel, préremplie.

import SwiftUI

struct VendorProfileMissingView: View {
    /// Titre de l'onglet où la vue s'affiche (« Tableau », « Lots »…).
    var title: LocalizedStringKey = "Producteurs"

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var requestCount = 0

    /// Courriel prérempli ; le destinataire est choisi dans l'app Mail.
    static let requestURL: URL? = {
        var components = URLComponents()
        components.scheme = "mailto"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Créer mon profil producteur LeGrenier"),
            URLQueryItem(
                name: "body",
                value: "Bonjour,\n\nJe souhaite vendre aux groupes de quartier sur LeGrenier.\n\nRaison sociale :\nType (ferme, coopérative, grossiste, boulangerie…) :\nQuartiers desservis :\n\nMerci !"
            ),
        ]
        return components.url
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ZStack(alignment: .bottomTrailing) {
                        StateIllustration(systemImage: "storefront.fill")
                            .symbolEffect(.bounce, value: appeared && !reduceMotion)
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.grenier)
                            .background(Color.fond, in: .circle)
                            .accessibilityHidden(true)
                    }

                    VStack(spacing: 8) {
                        Text("Crée ton profil producteur")
                            .font(.title2.bold())
                            .foregroundStyle(.texte)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("Ton compte n'est pas encore relié à un profil producteur. Une fois ton profil vérifié, tu publies des lots et tu vois la demande des quartiers.")
                            .font(.body)
                            .foregroundStyle(.texteSecondaire)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        step(1, "envelope.fill", "Envoie ta demande", "Raison sociale, type de commerce et quartiers desservis.")
                        step(2, "checkmark.seal.fill", "L'équipe LeGrenier vérifie", "Chaque producteur est vérifié avant de vendre aux familles.")
                        step(3, "shippingbox.fill", "Publie ton premier lot", "Tes paliers de prix, ta date limite, et c'est parti.")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .grenierCard(padding: 0)

                    Button {
                        requestCount += 1
                        if let url = Self.requestURL { openURL(url) }
                    } label: {
                        Label("Demander mon profil producteur", systemImage: "storefront.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.grenier)
                    .controlSize(.large)
                    .accessibilityHint("Ouvre un courriel prérempli pour demander ton profil producteur.")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .grenierBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .profileToolbar()
            .onAppear { appeared = true }
            .sensoryFeedback(.impact, trigger: requestCount)
        }
    }

    private func step(_ number: Int, _ systemImage: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
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
    VendorProfileMissingView(title: "Tableau")
}

#Preview("Sombre") {
    VendorProfileMissingView(title: "Tableau")
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorProfileMissingView(title: "Tableau")
        .dynamicTypeSize(.accessibility5)
}
