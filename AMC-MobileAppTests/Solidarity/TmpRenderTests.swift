import Testing
import SwiftUI
@testable import AMC_MobileApp

@MainActor
struct TmpSolidarityRender {
    @Test func render() throws {
        let configs: [(ColorScheme, DynamicTypeSize, String)] = [(.light, .large, "light"), (.dark, .large, "dark"), (.light, .accessibility5, "ax5")]
        for (scheme, size, tag) in configs {
            let view = VStack(spacing: 12) {
                SupportedHouseholdBanner(subsidyCents: 800)
                SuspendedBasketPicker(amountCents: .constant(500), shareTotalCents: 2_600)
                SuspendedBasketPicker(amountCents: .constant(1_250))
                SolidarityFundCard(groupName: "Parc-Ex Ouest", balanceCents: 8_400, basketsThisMonth: 12, basketCostCents: 2_600)
            }
            .padding()
            .frame(width: 393)
            .background(Color.fond)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, size)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.uiImage)
            try #require(image.pngData()).write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-willi-Documents-Source-AMC-MobileApp/11f39e84-f5a2-4b39-915a-c9ce86df8257/scratchpad/sol-\(tag).png"))
        }
    }
}
