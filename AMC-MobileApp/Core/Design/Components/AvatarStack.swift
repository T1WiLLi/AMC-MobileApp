import SwiftUI

/// Pile d'avatars à initiales qui se chevauchent (−10 pt), le dernier affiche « +21 » (maquette GroupCard).
/// Au plus 3 initiales sont affichées ; `extraCount` compte les membres en plus de celles-ci.
struct AvatarStack: View {
    let initials: [String]
    /// Nombre de membres en plus des initiales affichées (au plus 3).
    var extraCount = 0

    /// 34 pt à la taille par défaut, suit Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 34

    private static let tints: [Color] = [.grenier, .economie, .solidarite]

    /// Initiales réellement affichées.
    var shownInitials: [String] { Array(initials.prefix(3)) }

    /// Membres annoncés à VoiceOver : ceux affichés + le reste.
    var memberCount: Int { shownInitials.count + max(extraCount, 0) }

    var accessibilityText: String { FrenchPlural.count(memberCount, "membre") }

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(shownInitials.enumerated()), id: \.offset) { index, text in
                bubble(text, tint: Self.tints[index % Self.tints.count])
            }
            if extraCount > 0 {
                bubble("+\(extraCount)", tint: .solidarite)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func bubble(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(2)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            // 12 % comme les autres teintes du design system : Grenier y reste au-dessus de 4,5:1.
            .background(tint.opacity(0.12), in: .circle)
            .background(Color.surface, in: .circle)
            .overlay(Circle().stroke(Color.surface, lineWidth: 2))
    }
}

#Preview("Clair") {
    AvatarStack(initials: ["FB", "RK"], extraCount: 21)
        .padding()
        .grenierCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
}

#Preview("Sombre") {
    AvatarStack(initials: ["AM", "FB", "RK"], extraCount: 21)
        .padding()
        .grenierCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    AvatarStack(initials: ["AM", "FB", "RK"], extraCount: 121)
        .padding()
        .grenierCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .dynamicTypeSize(.accessibility5)
}
