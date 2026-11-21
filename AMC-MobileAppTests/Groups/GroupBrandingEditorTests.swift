import Foundation
import Testing
import UIKit
@testable import AMC_MobileApp

/// B-036 (T-152) : réglages de marque du groupe pour le coordonnateur.
@MainActor
struct GroupBrandingEditorTests {
    private let coordinator = FakeData.ID.amina
    private let groupId = FakeData.ID.saintMichel

    private func editor(userId: String? = nil) async throws -> (GroupBrandingEditorViewModel, AppRepositories) {
        let repositories = AppRepositories.fake(behavior: .instant)
        let group = try await repositories.groups.group(id: groupId)
        return (GroupBrandingEditorViewModel(repositories: repositories, group: group, userId: userId ?? coordinator), repositories)
    }

    @Test func everyAccentPresetPassesAAInLightAndDark() throws {
        for preset in GroupBrandingEditorViewModel.accentPresets {
            let light = try #require(BrandConfig.uiColor(hex: preset.light))
            let dark = try #require(BrandConfig.uiColor(hex: preset.dark))
            #expect(GroupTheme.meetsAA(light: light, dark: dark), "\(preset.name) ne passe pas le contraste AA")
        }
    }

    @Test func everyEmblemIsARealSFSymbol() {
        for symbol in GroupBrandingEditorViewModel.emblems {
            #expect(UIImage(systemName: symbol) != nil, "\(symbol) n'existe pas")
        }
    }

    @Test func opensWithTheCurrentBrandingAndNoChanges() async throws {
        let (editor, _) = try await editor()
        #expect(editor.displayName == "Saint-Michel en commun")
        #expect(editor.emblem == "leaf.fill")
        // L'accent seedé n'est pas un accent proposé : il est gardé comme « Couleur actuelle ».
        #expect(editor.accentPreset?.light == "#1E6B52")
        #expect(editor.accentPreset?.dark == "#5FC9A0")
        #expect(editor.availableAccents.count == GroupBrandingEditorViewModel.accentPresets.count + 1)
        #expect(!editor.hasChanges)
        #expect(!editor.canSave)
    }

    @Test func savesTheNewBrandingAndThemeFollows() async throws {
        let (editor, repositories) = try await editor()
        editor.displayName = "  Les Voisins  "
        editor.emblem = "carrot.fill"
        editor.accentId = "prune"
        editor.welcomeMessage = "Salut voisin !"
        #expect(editor.canSave)
        #expect(editor.previewTheme.usesGroupAccent)
        #expect(editor.previewTheme.displayName == "Les Voisins")

        let updated = try #require(await editor.save())
        #expect(editor.status == .saved)
        #expect(editor.savedCount == 1)
        #expect(updated.branding?.displayName == "Les Voisins")
        #expect(updated.branding?.accentLight == "#6E3A86")
        #expect(updated.branding?.accentDark == "#CDA6E6")
        let stored = try await repositories.groups.group(id: groupId)
        #expect(stored.resolvedBranding.emblem == "carrot.fill")
        #expect(stored.resolvedBranding.welcomeMessage == "Salut voisin !")
        #expect(!editor.hasChanges)
    }

    @Test func resetGoesBackToTheDefaultBrand() async throws {
        let (editor, repositories) = try await editor()
        editor.resetToDefault()
        #expect(editor.isDefault)
        #expect(!editor.previewTheme.usesGroupAccent)
        _ = try #require(await editor.save())
        let stored = try await repositories.groups.group(id: groupId)
        #expect(stored.branding == nil)
        #expect(stored.resolvedBranding.displayName == stored.name)
    }

    @Test func tooLongFieldsBlockSaving() async throws {
        let (editor, _) = try await editor()
        editor.displayName = String(repeating: "x", count: GroupBrandingEditorViewModel.maxDisplayNameLength + 1)
        #expect(editor.displayNameError != nil)
        #expect(!editor.canSave)
        editor.displayName = "Ok"
        editor.welcomeMessage = String(repeating: "x", count: GroupBrandingEditorViewModel.maxWelcomeLength + 1)
        #expect(editor.welcomeError != nil)
        #expect(!editor.canSave)
        #expect(await editor.save() == nil)
    }

    @Test func aNonCoordinatorCannotSave() async throws {
        let (editor, repositories) = try await editor(userId: "intrus")
        #expect(!editor.isCoordinator)
        editor.displayName = "Pris !"
        #expect(!editor.canSave)
        // Le dépôt refuse aussi, comme firestore.rules.
        await #expect(throws: AppError.permissionDenied) {
            try await repositories.groups.updateBranding(GroupBranding(displayName: "Pris !"),
                                                         ofGroup: groupId, byUserId: "intrus")
        }
    }
}
