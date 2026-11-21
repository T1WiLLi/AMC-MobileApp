import SwiftUI
import Testing
@testable import AMC_MobileApp

// TEMPORAIRE, NON COMMITÉ : rendu PNG pour vérification visuelle.
@MainActor
struct CelebrationRenderTmp {
    @Test func render() throws {
        let out = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-willi-Documents-Source-AMC-MobileApp/11f39e84-f5a2-4b39-915a-c9ce86df8257/scratchpad")
        let cases: [(String, ColorScheme, DynamicTypeSize)] = [("clair", .light, .large), ("sombre", .dark, .large), ("ax5", .light, .accessibility5)]
        for (name, scheme, size) in cases {
            let view = TierUnlockedCelebration(oldPriceCents: 260, newPriceCents: 210, unit: "kg", savingsPercent: 49, groupName: "Parc-Ex Ouest", onDismiss: {}).settled()
                .frame(width: 393, height: 852)
                .background(Color.surface)
                .environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, size)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let data = try #require(renderer.uiImage?.pngData())
            try data.write(to: out.appendingPathComponent("celebration-\(name).png"))
        }
    }
}
