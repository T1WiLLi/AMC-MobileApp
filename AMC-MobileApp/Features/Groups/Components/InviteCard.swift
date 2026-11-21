import SwiftUI

/// Carte d'invitation d'un groupe de quartier : QR à scanner, code d'invitation à dicter,
/// et partage d'un message prêt à envoyer (« il manque 1 famille pour débloquer −19 % »).
struct InviteCard: View {
    let group: NeighborhoodGroup
    /// Familles qui manquent pour le prochain palier ; nil s'il n'y a pas de palier en vue.
    var missingFamilies: Int?
    /// Rabais débloqué par ce palier, en % (19 pour −19 %).
    var discountPercent: Int?

    @ScaledMetric(relativeTo: .body) private var qrMaxSide: CGFloat = 180
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Label {
                    Text("Invite tes voisins")
                        .foregroundStyle(.texte)
                } icon: {
                    Image(systemName: "person.2.wave.2.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                        .symbolEffect(.wiggle, value: appeared && !reduceMotion && missingFamilies != nil)
                }
                .font(.title3.bold())
                Label {
                    Text(subtitle)
                } icon: {
                    Image(systemName: missingFamilies == nil ? "arrow.down.circle.fill" : "flag.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                }
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            QRCodeImage(Self.inviteURL(for: group).absoluteString,
                        accessibilityLabel: String(localized: "Code QR pour rejoindre \(group.name)"))
                .padding(12)
                .background(Color.surface, in: .rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.piste, lineWidth: 1.5))
                .frame(maxWidth: min(qrMaxSide, 280))

            VStack(spacing: 2) {
                Label("Code d'invitation", systemImage: "ticket.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.caption)
                    .foregroundStyle(.texteSecondaire)
                Text(group.inviteCode)
                    .font(.title2.bold())
                    .fontDesign(.monospaced)
                    .tracking(3)
                    .foregroundStyle(.texte)
                    .textSelection(.enabled)
                    .minimumScaleFactor(0.7)
                    .speechSpellsOutCharacters()
            }
            .accessibilityElement(children: .combine)

            ShareLink(
                item: shareMessage,
                subject: Text("Rejoins \(group.name) sur LeGrenier"),
                preview: SharePreview(String(localized: "Rejoins \(group.name) sur LeGrenier"), image: Image(systemName: GrenierSymbol.groups))
            ) {
                Label("Partager l'invitation", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .fontWeight(.semibold)
            .tint(.grenier)
        }
        .grenierCard(padding: 20)
        .onAppear { appeared = true }
    }

    private var subtitle: String {
        if let line = Self.urgencyLine(missingFamilies: missingFamilies, discountPercent: discountPercent) {
            return line.prefix(1).uppercased() + line.dropFirst()
        }
        return String(localized: "Plus on est de familles, plus le prix baisse.")
    }

    var shareMessage: String {
        Self.shareMessage(groupName: group.name, inviteCode: group.inviteCode,
                          missingFamilies: missingFamilies, discountPercent: discountPercent)
    }

    // MARK: Logique

    /// « il manque 1 famille pour débloquer −19 % » ; nil sans palier en vue.
    static func urgencyLine(missingFamilies: Int?, discountPercent: Int?) -> String? {
        guard let missingFamilies, missingFamilies > 0 else { return nil }
        let unit = missingFamilies > 1 ? "familles" : "famille"
        guard let discountPercent, discountPercent > 0 else {
            return String(localized: "il manque \(missingFamilies) \(unit) pour le prochain palier")
        }
        return String(localized: "il manque \(missingFamilies) \(unit) pour débloquer −\(discountPercent) %")
    }

    /// « Rejoins Parc-Ex Ouest sur Grenier : il manque 1 famille pour débloquer −19 %. Code d'invitation : PARCEX »
    static func shareMessage(groupName: String, inviteCode: String, missingFamilies: Int?, discountPercent: Int?) -> String {
        let head = if let line = urgencyLine(missingFamilies: missingFamilies, discountPercent: discountPercent) {
            String(localized: "Rejoins \(groupName) sur LeGrenier : \(line).")
        } else {
            String(localized: "Rejoins \(groupName) sur LeGrenier : on achète en gros entre voisins, directement aux producteurs.")
        }
        return String(localized: "\(head) Code d'invitation : \(inviteCode)")
    }

    /// Lien d'invitation encodé dans le QR : `grenier://join/PARCEX` (B-058), que l'app ouvre directement.
    static func inviteURL(for group: NeighborhoodGroup) -> URL {
        GroupRules.appInviteLink(for: group.inviteCode)
            ?? URL(string: "\(GroupRules.appScheme)://\(GroupRules.joinPath)")!
    }
}

#if DEBUG
private func invitePreview() -> some View {
    ScrollView {
        InviteCard(group: CardPreviewData.group, missingFamilies: 1, discountPercent: 19)
            .padding(16)
    }
    .grenierBackground()
}

#Preview("Clair") {
    invitePreview()
}

#Preview("Sombre") {
    invitePreview()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    invitePreview()
        .dynamicTypeSize(.accessibility5)
}
#endif
