import Foundation
import Testing
@testable import AMC_MobileApp

/// Photo stockée en mémoire, sans disque.
private struct MemoryPhotoStore: ProfilePhotoStoring {
    func store(_ data: Data, userId: String) async throws -> URL {
        URL(string: "file:///tmp/\(userId)-\(data.count).jpg")!
    }
}

@MainActor
struct AccountViewModelTests {
    private let userId = FakeData.ID.amina
    private let householdId = FakeData.ID.aminaHousehold

    /// Amina et un deuxième membre dans le même ménage, pour vérifier qu'on ne retire qu'elle.
    private func makeData() -> FakeUserRepository {
        let data = FakeData.montreal
        var households = data.households
        if let index = households.firstIndex(where: { $0.id == householdId }) {
            households[index].userIds.append("user-karim")
        }
        return FakeUserRepository(users: data.users, households: households)
    }

    private func makeModel(
        users: FakeUserRepository,
        auth: FakeAuthService = FakeAuthService(signedInUser: .sample, latency: .zero)
    ) -> AccountViewModel {
        var repositories = AppRepositories.fake(behavior: .instant)
        repositories.users = users
        return AccountViewModel(repositories: repositories, userId: userId, auth: auth, photoStore: MemoryPhotoStore())
    }

    // MARK: Modifier

    @Test func loadFillsNameAndPhoto() async {
        let model = makeModel(users: makeData())
        await model.load()
        #expect(model.displayName == "Amina Benali")
        #expect(model.photoURL == DemoMedia.aminaAvatar)
        #expect(!model.hasChanges)
        #expect(!model.canSave)
        #expect(model.initials == "AB")
    }

    @Test func saveWritesTrimmedNameAndPhoto() async throws {
        let users = makeData()
        let model = makeModel(users: users)
        await model.load()
        model.displayName = "  Amina B.  "
        await model.setPhoto(data: Data([1, 2, 3]))
        #expect(model.canSave)
        await model.save()

        let saved = try await users.user(id: userId)
        #expect(saved.displayName == "Amina B.")
        #expect(saved.photoURL == URL(string: "file:///tmp/\(userId)-3.jpg"))
        #expect(model.saveCount == 1)
        #expect(!model.hasChanges)
        #expect(model.saveError == nil)
    }

    @Test func emptyOrTooLongNameCannotBeSaved() async {
        let model = makeModel(users: makeData())
        await model.load()
        model.displayName = "   "
        #expect(model.displayNameError != nil)
        #expect(!model.canSave)
        model.displayName = String(repeating: "a", count: AccountViewModel.displayNameMaxLength + 1)
        #expect(model.displayNameError != nil)
        #expect(!model.canSave)
    }

    @Test func removePhotoAndDiscardChanges() async {
        let model = makeModel(users: makeData())
        await model.load()
        await model.setPhoto(data: Data([9]))
        #expect(model.hasChanges)
        model.removePhoto()
        #expect(model.photoURL == nil)
        model.displayName = "Autre"
        model.discardChanges()
        #expect(model.displayName == "Amina Benali")
        #expect(!model.hasChanges)
    }

    @Test func loadFailureIsShown() async {
        var repositories = AppRepositories.fake(behavior: .failing(.offline))
        repositories.users = FakeUserRepository(behavior: .failing(.offline))
        let model = AccountViewModel(
            repositories: repositories, userId: userId, auth: FakeAuthService(latency: .zero), photoStore: MemoryPhotoStore()
        )
        await model.load()
        #expect(model.loadState.error == .offline)
    }

    // MARK: Supprimer

    @Test func deletionNeedsTwoConfirmations() async {
        let auth = FakeAuthService(signedInUser: .sample, latency: .zero)
        let model = makeModel(users: makeData(), auth: auth)
        await model.confirmDeletion()       // sans premier temps : rien
        #expect(auth.deletedAccountIds.isEmpty)
        #expect(model.deletionState == .idle)

        model.requestDeletion()
        #expect(model.deletionState == .confirming)
        model.cancelDeletion()
        #expect(model.deletionState == .idle)
        #expect(auth.currentUser != nil)
    }

    @Test func deletionRemovesUserLeavesHouseholdAndSignsOut() async throws {
        let users = makeData()
        let auth = FakeAuthService(signedInUser: .sample, latency: .zero)
        auth.userData = users
        auth.dataUserId = userId
        let model = makeModel(users: users, auth: auth)
        await model.load()

        model.requestDeletion()
        await model.confirmDeletion()

        #expect(model.deletionState == .deleted)
        #expect(auth.currentUser == nil)
        #expect(auth.deletedAccountIds == [AuthUser.sample.id])
        await #expect(throws: AppError.notFound) { try await users.user(id: userId) }
        let household = try await users.household(id: householdId)
        #expect(household.userIds == [FakeData.ID.yacine, "user-karim"])
    }

    @Test func deletionEndsSession() async {
        let auth = FakeAuthService(signedInUser: .sample, latency: .zero)
        let session = SessionViewModel(auth: auth)
        let observer = Task { await session.observeSession() }
        defer { observer.cancel() }
        let model = makeModel(users: makeData(), auth: auth)

        model.requestDeletion()
        await model.confirmDeletion()
        for _ in 0..<20 where session.currentUser != nil { await Task.yield() }
        #expect(session.currentUser == nil)
        #expect(session.state == .signedOut)
    }

    @Test func recentLoginRequiredAsksToReconnectAndKeepsData() async throws {
        let users = makeData()
        let auth = FakeAuthService(signedInUser: .sample, nextError: .requiresRecentLogin, latency: .zero)
        auth.userData = users
        auth.dataUserId = userId
        let model = makeModel(users: users, auth: auth)

        model.requestDeletion()
        await model.confirmDeletion()

        #expect(model.deletionState == .needsReauthentication)
        #expect(auth.currentUser != nil)
        #expect(try await users.user(id: userId).id == userId)
        model.dismissDeletionMessage()
        #expect(model.deletionState == .idle)
    }

    @Test func networkFailureShowsMessage() async {
        let auth = FakeAuthService(signedInUser: .sample, nextError: .network, latency: .zero)
        let model = makeModel(users: makeData(), auth: auth)
        model.requestDeletion()
        await model.confirmDeletion()
        #expect(model.deletionState == .failed(AuthError.network.errorDescription!))
    }
}
