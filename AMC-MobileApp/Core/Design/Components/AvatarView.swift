import SwiftUI

/// Avatar d'une personne (T-122) : sa photo en fondu, sinon ses initiales sur un cercle teinté.
/// Réutilisable partout (compte, profil, membres). Taille fixe : passe une `@ScaledMetric` pour suivre Dynamic Type.
struct AvatarView: View {
    let name: String
    let photoURL: URL?
    var size: CGFloat = 44
    var tint: Color = .grenier
    /// Anneau clair autour (avatar posé sur une image ou une autre surface).
    var showsRing = false

    var body: some View {
        MediaImage(url: photoURL) {
            Circle()
                .fill(tint.opacity(0.14))
                .background(Color.surface, in: .circle)
                .overlay {
                    Text(Self.initials(of: name))
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(size * 0.12)
                }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay {
            if showsRing {
                Circle().stroke(Color.surface, lineWidth: max(2, size * 0.04))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(photoURL == nil ? "Avatar de \(name)" : "Photo de \(name)")
        .accessibilityAddTraits(.isImage)
    }

    /// « Amina Benali » → « AB » ; « ? » si le nom est vide.
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
        let letters = words.prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// Photo d'un groupe de quartier (T-122) : sa photo, sinon ses initiales sur un dégradé Grenier.
struct GroupAvatarView: View {
    let group: NeighborhoodGroup
    var size: CGFloat = 44
    var showsRing = false

    var body: some View {
        MediaImage(url: group.photoURL) {
            Circle()
                .fill(LinearGradient(colors: [.grenier, .economie], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Text(AvatarView.initials(of: group.neighborhood.isEmpty ? group.name : group.neighborhood))
                        .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.onAccent)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(size * 0.12)
                }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay {
            if showsRing {
                Circle().stroke(Color.surface, lineWidth: max(3, size * 0.05))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(group.photoURL == nil ? "Initiales du groupe \(group.name)" : "Photo du groupe \(group.name)")
        .accessibilityAddTraits(.isImage)
    }
}

#if DEBUG
#Preview("Avatars") {
    HStack(spacing: 16) {
        AvatarView(name: "Amina Benali", photoURL: MediaURL.asset("AvatarAmina"), size: 64)
        AvatarView(name: "Karim Haddad", photoURL: nil, size: 64)
        AvatarView(name: "Sofia", photoURL: MediaURL.asset("AvatarVoisin1"), size: 64, showsRing: true)
        GroupAvatarView(group: CardPreviewData.group, size: 64)
    }
    .padding()
    .grenierBackground()
    .environment(\.appContext, .instant)
}

#Preview("Sombre") {
    HStack(spacing: 16) {
        AvatarView(name: "Amina Benali", photoURL: nil, size: 64)
        GroupAvatarView(group: FakeData.montreal.groups[0], size: 64, showsRing: true)
    }
    .padding()
    .grenierBackground()
    .environment(\.appContext, .instant)
    .preferredColorScheme(.dark)
}
#endif
