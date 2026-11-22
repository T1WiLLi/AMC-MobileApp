import Testing
@testable import AMC_MobileApp

@MainActor
struct ProductUnitPickerTests {
    @Test func optionsMatchLotShareUnitsPlusDozen() {
        #expect(ProductUnitPicker.options == ["kg", "g", "lb", "L", "mL", "unité", "douzaine"])
    }

    @Test func legacyFreeTextUnitStaysSelectable() {
        #expect(ProductUnitPicker.menuOptions(current: "sac de 10 kg").first == "sac de 10 kg")
        #expect(ProductUnitPicker.menuOptions(current: "kg") == ProductUnitPicker.options)
        #expect(ProductUnitPicker.menuOptions(current: "") == ProductUnitPicker.options)
    }
}
