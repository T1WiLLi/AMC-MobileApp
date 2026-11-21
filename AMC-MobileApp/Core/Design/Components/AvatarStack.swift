import SwiftUI

/// Pile d'avatars à initiales qui se chevauchent (−10 pt), le dernier affiche « +21 » (maquette GroupCard).
struct AvatarStack: View {
    let initials: [String]
    /// Nombre de membres en plus de ceux affichés.
    var extraCount = 0
    var size: CGFloat = 34

    private static let tints: [Color] = [.grenier, .economie, .solidarite]

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(initials.prefix(3).enumerated()), id: \.offset) { index, text in
                bubble(text, tint: Self.tints[index % Self.tints.count])
            }
            if extraCount > 0 {
                bubble("+\(extraCount)", tint: .solidarite)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(initials.count + extraCount) membres")
    }

    private func bubble(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: .circle)
            .background(Color.surface, in: .circle)
            .overlay(Circle().stroke(Color.surface, lineWidth: 2))
    }
}

#Preview {
    AvatarStack(initials: ["FB", "RK"], extraCount: 21)
        .padding()
}
