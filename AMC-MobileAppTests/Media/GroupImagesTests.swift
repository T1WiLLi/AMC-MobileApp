import Foundation
import Testing
import UIKit
@testable import AMC_MobileApp

/// T-122 : photos de profil, photos et bannières de groupe (base64 Firestore, fake en mémoire).
@MainActor
struct GroupImagesTests {
    private let coordinator = FakeData.ID.amina
    private let groupId = FakeData.ID.saintMichel

    /// Photo de test (dégradé, pour que la compression ait du travail).
    private func photo(width: CGFloat = 2_000, height: CGFloat = 1_000) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            for x in stride(from: 0, to: width, by: 20) {
                UIColor(hue: x / width, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: x, y: 0, width: 20, height: height))
            }
        }.pngData()!
    }

    // MARK: Références

    @Test func mediaPathRoundTripsThroughItsURL() throws {
        for path in [MediaPath.userAvatar(userId: "u1"), .groupPhoto(groupId: "g1"), .groupBanner(groupId: "g1"),
                     .pickupPhoto(pointId: "pickup-1")] {
            let url = path.url(version: 42)
            #expect(url.scheme == "grenier-media")
            #expect(MediaURL.source(of: url) == .media(path))
            #expect(MediaURL.version(of: url) == 42)
        }
        #expect(MediaPath.groupBanner(groupId: "g1").documentPath == "groups/g1/media/banner")
        #expect(MediaPath.userAvatar(userId: "u1").documentPath == "users/u1/media/avatar")
        #expect(MediaPath.pickupPhoto(pointId: "pickup-1").documentPath == "pickupPoints/pickup-1/media/photo")
        #expect(MediaPath(documentPath: "groups/g1/media/logo") == nil)
        #expect(MediaURL.source(of: MediaURL.asset("BannerSaintMichel")) == .asset("BannerSaintMichel"))
        #expect(MediaURL.source(of: URL(string: "https://example.com/a.jpg")!) == .remote(URL(string: "https://example.com/a.jpg")!))
    }

    // MARK: Recadrage

    @Test func aspectFillCentersAndCoversTheTarget() {
        let rect = ImageProcessing.aspectFillRect(source: CGSize(width: 2_000, height: 1_000),
                                                  target: CGSize(width: 400, height: 400))
        #expect(rect.height == 400)
        #expect(rect.width == 800)
        #expect(rect.minX == -200)
        #expect(rect.minY == 0)
    }

    @Test func prepareCropsToSpecAndStaysUnderTheFirestoreLimit() throws {
        let banner = try ImageProcessing.prepare(photo(), spec: .banner)
        #expect(banner.width == 1_200)
        #expect(banner.height == 450)
        #expect(banner.jpeg.count <= ImageSpec.banner.maxBytes)
        let decoded = try #require(UIImage(data: banner.jpeg))
        #expect(decoded.size == CGSize(width: 1_200, height: 450))

        let square = try ImageProcessing.prepare(photo(width: 600, height: 3_000), spec: .square)
        #expect(UIImage(data: square.jpeg)?.size == CGSize(width: 400, height: 400))
        #expect(square.jpeg.count <= ImageSpec.square.maxBytes)
    }

    @Test func prepareRejectsSomethingThatIsNotAnImage() {
        #expect(throws: AppError.self) {
            try ImageProcessing.prepare(Data("pas une image".utf8), spec: .square)
        }
    }

    // MARK: Dépôts fake

    @Test func onlyACoordinatorChangesGroupImages() async throws {
        let groups = FakeGroupRepository(groups: FakeData.montreal.groups)
        let url = MediaPath.groupBanner(groupId: groupId).url(version: 1)
        try await groups.updateImage(.banner, url: url, ofGroup: groupId, byUserId: coordinator)
        #expect(try await groups.group(id: groupId).bannerURL == url)

        await #expect(throws: AppError.permissionDenied) {
            try await groups.updateImage(.photo, url: url, ofGroup: groupId, byUserId: "user-voisin")
        }
        await #expect(throws: AppError.notFound) {
            try await groups.updateImage(.photo, url: url, ofGroup: "group-inconnu", byUserId: coordinator)
        }
        try await groups.updateImage(.banner, url: nil, ofGroup: groupId, byUserId: coordinator)
        #expect(try await groups.group(id: groupId).bannerURL == nil)
    }

    @Test func fakeImageStoreSavesVersionedURLs() async throws {
        let store = FakeImageStore()
        let image = PreparedImage(jpeg: Data([1, 2, 3]), width: 400, height: 400)
        let path = MediaPath.groupPhoto(groupId: groupId)
        let first = try await store.save(image, at: path)
        let second = try await store.save(image, at: path)
        #expect(first != second)
        #expect(try await store.imageData(at: path) == Data([1, 2, 3]))
        try await store.delete(at: path)
        await #expect(throws: AppError.notFound) { try await store.imageData(at: path) }
    }

    // MARK: Éditeur du coordinateur

    private func makeEditor(userId: String) -> (GroupImageEditorViewModel, AppRepositories) {
        let repositories = AppRepositories.fake(behavior: .instant)
        return (GroupImageEditorViewModel(repositories: repositories, groupId: groupId, userId: userId), repositories)
    }

    @Test func pickShowsAPreviewThenConfirmUploadsAndSetsTheGroupBanner() async throws {
        let (editor, repositories) = makeEditor(userId: coordinator)
        await editor.pick(photo(), kind: .banner)
        #expect(editor.status == .ready)
        #expect(editor.isPresentingPreview)
        #expect(editor.pending?.image.width == 1_200)

        let group = try #require(await editor.confirm())
        #expect(editor.status == .succeeded)
        #expect(editor.progress == 1)
        #expect(editor.successCount == 1)
        let url = try #require(group.bannerURL)
        #expect(MediaURL.source(of: url) == .media(.groupBanner(groupId: groupId)))
        #expect(try await repositories.groups.group(id: groupId).bannerURL == url)
        #expect(try await repositories.images.imageData(at: .groupBanner(groupId: groupId)).isEmpty == false)

        editor.dismiss()
        #expect(!editor.isPresentingPreview)
        #expect(editor.status == .idle)
    }

    @Test func aNonCoordinatorGetsAnErrorAndCanRetry() async {
        let (editor, _) = makeEditor(userId: "user-voisin")
        await editor.pick(photo(), kind: .photo)
        let group = await editor.confirm()
        #expect(group == nil)
        #expect(editor.error == .permissionDenied)
        #expect(editor.progress == 0)
        // L'aperçu reste : « Réessayer » renvoie la même image.
        #expect(editor.pending != nil)
        #expect(await editor.retry() == nil)
        #expect(editor.error == .permissionDenied)
    }

    @Test func pickingSomethingUnreadableFailsWithoutPreview() async {
        let (editor, _) = makeEditor(userId: coordinator)
        await editor.pick(Data("texte".utf8), kind: .photo)
        #expect(editor.pending == nil)
        if case .failed(.invalidInput) = editor.status {} else {
            Issue.record("Attendu : .failed(.invalidInput), obtenu \(editor.status)")
        }
    }

    @Test func removeClearsTheGroupPhoto() async throws {
        let (editor, repositories) = makeEditor(userId: coordinator)
        #expect(try await repositories.groups.group(id: groupId).photoURL != nil)
        let group = try #require(await editor.remove(.photo))
        #expect(group.photoURL == nil)
        #expect(editor.successCount == 1)
        #expect(editor.status == .idle)
    }

    // MARK: Photo de profil

    @Test func profilePhotoIsCroppedAndStoredAsTheUserAvatar() async throws {
        let store = FakeImageStore()
        let url = try await ImageStoreProfilePhotoStore(imageStore: store).store(photo(), userId: coordinator)
        #expect(MediaURL.source(of: url) == .media(.userAvatar(userId: coordinator)))
        let saved = try await store.imageData(at: .userAvatar(userId: coordinator))
        #expect(UIImage(data: saved)?.size == CGSize(width: 400, height: 400))
    }

    @Test func groupDetailKnowsItsCoordinator() async {
        let repositories = AppRepositories.fake(behavior: .instant)
        let detail = GroupDetailViewModel(repositories: repositories, householdId: FakeData.ID.aminaHousehold,
                                          groupId: groupId, userId: coordinator)
        await detail.load()
        #expect(detail.isCoordinator)
        let member = GroupDetailViewModel(repositories: repositories, householdId: FakeData.ID.aminaHousehold,
                                          groupId: groupId, userId: "user-voisin")
        await member.load()
        #expect(!member.isCoordinator)
    }
}
